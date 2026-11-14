//! stdio 上游：起一个子进程，走按行分隔的 JSON-RPC（MCP 的 stdio 传输）。从 mcp-rust 搬来。
//!
//! 单 actor 独占子进程和挂起请求表，外部只通过 mpsc 说话。三条必须做对的事（mcp-rust 原注释）：
//! 1. 进程退出时把挂起的请求全部以错误收尾，否则调用方永久悬挂；
//! 2. 不可用期间立刻回错误，不让调用方等超时；
//! 3. 杀进程组而不是只杀进程：npx / uv 会留孙子进程。

use super::{after_run, fetch_catalog, gw_id, initialize_params, Command, Handshake, Inbound, Rpc, RunOutcome, Shared, Spec, INIT_TIMEOUT, MAX_MESSAGE_BYTES};
use crate::error::UpstreamError;
use crate::jsonrpc::{code, Id, Kind, Message};
use crate::platform;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::process::Stdio;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{ChildStdin, ChildStdout};
use tokio::sync::{broadcast, mpsc, oneshot};
use tokio_util::sync::CancellationToken;

struct Pending {
    reply: oneshot::Sender<Result<Message, UpstreamError>>,
    /// 客户端原来的 id。多个客户端的 id 会撞，发给上游时换成网关自己的，回来再换回去。
    downstream_id: Option<Id>,
    method: String,
    deadline: Instant,
    limit: Duration,
    started: Instant,
}

pub(crate) async fn supervisor(
    spec: Spec,
    mut rx: mpsc::Receiver<Command>,
    sh: Arc<Shared>,
    inbound: broadcast::Sender<Inbound>,
    shutdown: CancellationToken,
) {
    loop {
        if shutdown.is_cancelled() {
            return;
        }
        let outcome = run_once(&spec, &mut rx, &sh, &inbound, &shutdown).await;
        if !after_run(outcome, &sh, &mut rx, &shutdown).await {
            return;
        }
    }
}

/// 算出要跑的程序、参数和环境。这里出错都是配置问题（找不到命令、缺变量），重试也没用。
fn prepare(spec: &Spec) -> Result<(std::path::PathBuf, Vec<String>, HashMap<String, String>), String> {
    let command = spec.expand(spec.entry.command.as_deref().unwrap_or_default())?;
    let args = spec.entry.args.clone().unwrap_or_default().iter().map(|a| spec.expand(a)).collect::<Result<Vec<_>, _>>()?;
    let mut env: HashMap<String, String> = platform::BASE_ENV.iter().filter_map(|k| Some((k.to_string(), std::env::var(k).ok()?))).collect();
    if let Some(p) = &spec.login_path {
        env.insert("PATH".into(), p.clone());
    }
    for (k, v) in &spec.global_env {
        env.insert(k.clone(), spec.expand(v)?);
    }
    for (k, v) in spec.entry.env.clone().unwrap_or_default() {
        env.insert(k, spec.expand(&v)?);
    }
    let path = env.get("PATH").cloned().unwrap_or_default();
    let program = platform::find_program(&command, &path).ok_or_else(|| format!("找不到命令「{command}」（PATH 里没有它）"))?;
    Ok((program, args, env))
}

async fn run_once(
    spec: &Spec,
    rx: &mut mpsc::Receiver<Command>,
    sh: &Arc<Shared>,
    inbound: &broadcast::Sender<Inbound>,
    shutdown: &CancellationToken,
) -> RunOutcome {
    let name = &spec.name;
    let (program, args, env) = match prepare(spec) {
        Ok(v) => v,
        Err(why) => return RunOutcome::ConfigError(why),
    };
    sh.set_starting(format!("正在启动 {} {}", spec.entry.command.as_deref().unwrap_or_default(), args.join(" ")));

    let mut cmd = tokio::process::Command::new(&program);
    cmd.args(&args)
        .env_clear()
        .envs(&env)
        .current_dir(platform::home_dir())
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    platform::prepare_child(&mut cmd);
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => return RunOutcome::Failed(format!("启动 {} 失败：{e}", program.display())),
    };
    let pid = child.id();
    if let Some(pid) = pid {
        crate::children::add(name, pid, &program.display().to_string());
    }
    let stdin = child.stdin.take().expect("stdin piped");
    let stdout = child.stdout.take().expect("stdout piped");
    let stderr = child.stderr.take().expect("stderr piped");
    let stderr_task = tokio::spawn(pump_stderr(stderr, sh.clone()));

    let mut io = StdioRpc { stdin, reader: BufReader::new(stdout), next: 0, inbound: inbound.clone(), name: name.clone() };

    // ── 握手 + 拉清单 ─────────────────────────────────────────────
    let ready = async {
        let init = io.rpc("initialize", initialize_params(), INIT_TIMEOUT).await.map_err(|e| format!("initialize 没有完成：{e}"))?;
        let hs = Handshake::parse(&init);
        write_msg(&mut io.stdin, &Message::notification("notifications/initialized", None))
            .await
            .map_err(|e| format!("写 notifications/initialized 失败：{e}"))?;
        let catalog = fetch_catalog(&mut io, &hs.capabilities, sh).await?;
        Ok::<_, String>((hs, catalog))
    };
    let (hs, catalog) = tokio::select! {
        r = ready => match r {
            Ok(v) => v,
            Err(why) => {
                cleanup(&mut child, pid, stderr_task).await;
                return RunOutcome::Failed(with_stderr(why, sh));
            }
        },
        _ = shutdown.cancelled() => {
            cleanup(&mut child, pid, stderr_task).await;
            return RunOutcome::Shutdown;
        }
    };
    sh.set_ready(pid, hs, catalog);

    // ── 主循环 ───────────────────────────────────────────────────
    // 超时用固定 tick 扫描，不给每个请求开定时器（精度 ±500ms 对分钟级限额无所谓）。
    let mut sweep = tokio::time::interval(Duration::from_millis(500));
    sweep.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    let mut pending: HashMap<Id, Pending> = HashMap::new();
    let mut line = String::new();
    let StdioRpc { mut stdin, mut reader, mut next, .. } = io;

    let outcome = loop {
        tokio::select! {
            biased;
            _ = shutdown.cancelled() => break RunOutcome::Shutdown,
            status = child.wait() => {
                break RunOutcome::Failed(with_stderr(format!("进程退出了（{}）", status.map(|s| s.to_string()).unwrap_or_else(|e| e.to_string())), sh));
            }
            n = read_line_capped(&mut reader, &mut line) => match n {
                Ok(0) => break RunOutcome::Failed(with_stderr("进程关闭了标准输出".into(), sh)),
                Ok(_) => {
                    dispatch_line(&line, name, inbound, &mut pending, &mut stdin).await;
                    line.clear();
                }
                Err(e) => break RunOutcome::Failed(format!("读标准输出失败：{e}")),
            },
            cmd = rx.recv() => match cmd {
                None => break RunOutcome::Shutdown,
                Some(Command::Restart) => break RunOutcome::Restart,
                Some(Command::Notify(msg)) => {
                    if let Err(e) = write_msg(&mut stdin, &msg).await {
                        break RunOutcome::Failed(format!("写标准输入失败：{e}"));
                    }
                }
                Some(Command::Cancel { id, reason }) => {
                    let key = pending.iter().find(|(_, p)| p.downstream_id.as_ref() == Some(&id)).map(|(k, _)| k.clone());
                    if let Some(k) = key {
                        let p = pending.remove(&k).unwrap();
                        let _ = write_msg(&mut stdin, &super::cancelled(&k, &reason)).await;
                        let _ = p.reply.send(Err(UpstreamError::Unavailable { slug: name.to_string(), reason: "客户端取消了这个请求".into() }));
                    }
                }
                Some(Command::Call { mut msg, timeout, reply }) => {
                    next += 1;
                    let id = gw_id(next);
                    let downstream_id = msg.id.replace(id.clone());
                    let method = msg.method_str().to_string();
                    if let Err(e) = write_msg(&mut stdin, &msg).await {
                        let _ = reply.send(Err(UpstreamError::Transport(name.to_string(), e)));
                        break RunOutcome::Failed("写标准输入失败".into());
                    }
                    let now = Instant::now();
                    pending.insert(id, Pending { reply, downstream_id, method, deadline: now + timeout, limit: timeout, started: now });
                }
            },
            _ = sweep.tick() => {
                let now = Instant::now();
                let expired: Vec<Id> = pending.iter().filter(|(_, p)| p.deadline <= now).map(|(k, _)| k.clone()).collect();
                for k in expired {
                    if let Some(p) = pending.remove(&k) {
                        let _ = p.reply.send(Err(UpstreamError::Timeout {
                            slug: name.to_string(), method: p.method,
                            elapsed_ms: p.started.elapsed().as_millis() as u64, limit_ms: p.limit.as_millis() as u64,
                        }));
                    }
                }
            }
        }
    };

    // 收尾：挂起的请求一个都不能漏。
    for (_, p) in pending.drain() {
        let _ = p.reply.send(Err(UpstreamError::Unavailable { slug: name.to_string(), reason: format!("处理 {} 时上游退出了", p.method) }));
    }
    cleanup(&mut child, pid, stderr_task).await;
    outcome
}

/// 把 stderr 最后几行接在原因后面：MCP 启动失败的原因几乎都在 stderr 里。
fn with_stderr(why: String, sh: &Shared) -> String {
    let st = sh.status();
    let tail: Vec<&str> = st.log.iter().rev().filter(|l| l.level == "stderr").take(3).map(|l| l.text.as_str()).collect();
    match tail.first() {
        Some(last) => format!("{why}：{last}"),
        None => why,
    }
}

/// 握手阶段的一问一答。等目标响应期间收到的通知照样转发；上游发来的请求回"不支持"，免得它一直等。
struct StdioRpc {
    stdin: ChildStdin,
    reader: BufReader<ChildStdout>,
    next: u64,
    inbound: broadcast::Sender<Inbound>,
    name: Arc<str>,
}

impl Rpc for StdioRpc {
    async fn rpc(&mut self, method: &str, params: Value, timeout: Duration) -> Result<Value, String> {
        self.next += 1;
        let id = gw_id(self.next);
        write_msg(&mut self.stdin, &Message::request(id.clone(), method, Some(params))).await.map_err(|e| format!("写失败：{e}"))?;
        let deadline = Instant::now() + timeout;
        let mut line = String::new();
        loop {
            let left = deadline.saturating_duration_since(Instant::now());
            line.clear();
            let n = match tokio::time::timeout(left, read_line_capped(&mut self.reader, &mut line)).await {
                Err(_) => return Err(format!("{} 秒内没有回应", timeout.as_secs())),
                Ok(Err(e)) => return Err(format!("读失败：{e}")),
                Ok(Ok(n)) => n,
            };
            if n == 0 {
                return Err("进程关闭了标准输出".into());
            }
            let Ok(msg) = serde_json::from_str::<Message>(line.trim()) else { continue };
            match msg.kind() {
                Kind::Response if msg.id.as_ref() == Some(&id) => {
                    if let Some(e) = &msg.error {
                        return Err(format!("{method} 出错：{}", e.get("message").and_then(Value::as_str).unwrap_or("未知错误")));
                    }
                    return Ok(msg.result.unwrap_or(json!({})));
                }
                Kind::Notification => {
                    let _ = self.inbound.send(Inbound::Notification(msg));
                }
                Kind::Request => {
                    let err = Message::error(msg.id.clone().unwrap_or(Id::Null), code::METHOD_NOT_FOUND, format!("MCP Station 不支持 {}", msg.method_str()));
                    let _ = write_msg(&mut self.stdin, &err).await;
                }
                _ => tracing::debug!(mcp = %self.name, "握手期间收到非预期报文"),
            }
        }
    }
}

async fn dispatch_line(line: &str, name: &str, inbound: &broadcast::Sender<Inbound>, pending: &mut HashMap<Id, Pending>, stdin: &mut ChildStdin) {
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return;
    }
    // 有的 MCP 会往 stdout 打启动横幅（违反规范），跳过就好。
    let Ok(msg) = serde_json::from_str::<Message>(trimmed) else { return };
    match msg.kind() {
        Kind::Response => {
            let Some(id) = msg.id.clone() else { return };
            if let Some(p) = pending.remove(&id) {
                let mut out = msg;
                out.id = p.downstream_id;
                let _ = p.reply.send(Ok(out));
            }
        }
        Kind::Notification => {
            let _ = inbound.send(Inbound::Notification(msg));
        }
        Kind::Request => {
            tracing::warn!(mcp = %name, method = %msg.method_str(), "上游发来了请求，网关没有声明这个能力，回 MethodNotFound");
            let err = Message::error(msg.id.clone().unwrap_or(Id::Null), code::METHOD_NOT_FOUND, format!("MCP Station 不支持 {}", msg.method_str()));
            let _ = write_msg(stdin, &err).await;
        }
        Kind::Malformed => {}
    }
}

async fn cleanup(child: &mut tokio::process::Child, pid: Option<u32>, stderr_task: tokio::task::JoinHandle<()>) {
    if let Some(pid) = pid {
        platform::terminate_tree(pid);
        if tokio::time::timeout(Duration::from_secs(3), child.wait()).await.is_err() {
            platform::kill_tree(pid);
        }
        crate::children::remove(pid);
    }
    let _ = child.kill().await;
    let _ = child.wait().await;
    stderr_task.abort();
}

async fn write_msg(w: &mut ChildStdin, msg: &Message) -> std::io::Result<()> {
    let mut buf = serde_json::to_vec(msg).map_err(std::io::Error::other)?;
    buf.push(b'\n');
    w.write_all(&buf).await?;
    w.flush().await
}

async fn read_line_capped(reader: &mut BufReader<ChildStdout>, out: &mut String) -> std::io::Result<usize> {
    let n = reader.read_line(out).await?;
    if out.len() > MAX_MESSAGE_BYTES {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "单行报文超过上限"));
    }
    Ok(n)
}

async fn pump_stderr(stderr: tokio::process::ChildStderr, sh: Arc<Shared>) {
    let mut lines = BufReader::new(stderr).lines();
    while let Ok(Some(l)) = lines.next_line().await {
        if !l.trim().is_empty() {
            sh.log("stderr", l);
        }
    }
}
