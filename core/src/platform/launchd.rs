//! macOS 开机自启：用户级 LaunchAgent。由 `mcp-core install` 完成安装 / 升级 / 重启，Swift 和以后的别的界面只调这条命令。
//!
//! 为什么不用 SMAppService：它要求 plist 和二进制都在 App 包里，而重装 App（rm -rf 再拷）会把正在跑的内核连带断掉；
//! 它也要求正式签名。所以内核复制到数据目录的 bin/ 下运行，和 App 包解耦。

use crate::paths;
use serde_json::{json, Value};
use std::path::PathBuf;
use std::process::Command;
use std::time::{Duration, Instant};

pub fn label() -> String {
    if paths::is_dev() { "com.example.mcp-station.core.dev".into() } else { "com.example.mcp-station.core".into() }
}

fn plist_path() -> PathBuf {
    super::home_dir().join("Library/LaunchAgents").join(format!("{}.plist", label()))
}

fn domain() -> String {
    format!("gui/{}", nix::unistd::getuid())
}

fn target() -> String {
    format!("{}/{}", domain(), label())
}

fn launchctl(args: &[&str]) -> (bool, String) {
    match Command::new("/bin/launchctl").args(args).output() {
        Ok(o) => (o.status.success(), format!("{}{}", String::from_utf8_lossy(&o.stdout), String::from_utf8_lossy(&o.stderr))),
        Err(e) => (false, e.to_string()),
    }
}

fn xml(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;")
}

fn plist(bin: &str) -> String {
    let log = paths::logs_dir().join("launchd.log");
    let env = if paths::is_dev() {
        format!(
            "  <key>EnvironmentVariables</key>\n  <dict><key>MCPSTATION_HOME</key><string>{}</string></dict>\n",
            xml(&paths::data_dir().display().to_string())
        )
    } else {
        String::new()
    };
    format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>{label}</string>
  <key>ProgramArguments</key><array><string>{bin}</string><string>run</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>StandardOutPath</key><string>{log}</string>
  <key>StandardErrorPath</key><string>{log}</string>
{env}</dict>
</plist>
"#,
        label = label(),
        bin = xml(bin),
        log = xml(&log.display().to_string()),
    )
}

/// 安装或升级并确保在跑。二进制或 plist 有变化、或 `restart` 为真时重启它。最多等 10 秒，直到新进程写出 runtime.json。
pub fn install(restart: bool) -> Result<Value, String> {
    let started = Instant::now();
    std::fs::create_dir_all(paths::bin_dir()).map_err(|e| e.to_string())?;
    std::fs::create_dir_all(paths::logs_dir()).map_err(|e| e.to_string())?;

    // 1. 二进制：内容不同才换。先写 .new 再 rename，绝不原地覆盖正在跑的文件（inode 不变会被系统按签名失效杀掉）。
    let me = std::env::current_exe().map_err(|e| e.to_string())?;
    let bin = paths::bin_dir().join("mcp-core");
    let mine = std::fs::read(&me).map_err(|e| format!("读不了 {}：{e}", me.display()))?;
    let binary_changed = std::fs::read(&bin).map(|b| b != mine).unwrap_or(true);
    if binary_changed && me != bin {
        let tmp = paths::bin_dir().join("mcp-core.new");
        std::fs::write(&tmp, &mine).map_err(|e| e.to_string())?;
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o755)).map_err(|e| e.to_string())?;
        std::fs::rename(&tmp, &bin).map_err(|e| e.to_string())?;
    }

    // 2. plist：内容不同才重写。
    let p = plist_path();
    let want = plist(&bin.display().to_string());
    let plist_changed = std::fs::read_to_string(&p).map(|s| s != want).unwrap_or(true);
    if plist_changed {
        std::fs::create_dir_all(p.parent().unwrap()).map_err(|e| e.to_string())?;
        std::fs::write(&p, &want).map_err(|e| e.to_string())?;
    }

    // 3. 载入 / 重启。
    let old_pid = read_runtime_pid();
    launchctl(&["enable", &target()]);
    let loaded = launchctl(&["print", &target()]).0;
    if loaded && plist_changed {
        launchctl(&["bootout", &target()]);
        std::thread::sleep(Duration::from_millis(500));
    }
    if !loaded || plist_changed {
        let (ok, out) = launchctl(&["bootstrap", &domain(), &p.display().to_string()]);
        if !ok && !launchctl(&["print", &target()]).0 {
            return Err(format!("launchctl bootstrap 失败：{}", out.trim()));
        }
    } else if binary_changed || restart {
        launchctl(&["kickstart", "-k", &target()]);
    }

    // 4. 等新进程起来。
    let deadline = Instant::now() + Duration::from_secs(10);
    while Instant::now() < deadline {
        if let Some(rt) = read_runtime() {
            let pid = rt.get("pid").and_then(Value::as_u64).unwrap_or(0) as u32;
            // 要求重启的情况下，得等到换了新进程才算数
            let expect_new = binary_changed || restart || !loaded || plist_changed;
            let fresh = !expect_new || Some(pid) != old_pid;
            if pid > 0 && super::alive(pid) && fresh {
                return Ok(json!({ "ok": true, "pid": pid, "label": label(), "elapsedMs": started.elapsed().as_millis() as u64,
                                  "binaryChanged": binary_changed, "controlPort": rt.get("controlPort") }));
            }
        }
        std::thread::sleep(Duration::from_millis(200));
    }
    Err(format!("内核 10 秒内没有起来，看 {} 下的日志", paths::logs_dir().display()))
}

pub fn uninstall() -> Result<Value, String> {
    let (_, out) = launchctl(&["bootout", &target()]);
    let _ = std::fs::remove_file(plist_path());
    Ok(json!({ "ok": true, "label": label(), "output": out.trim() }))
}

/// 内核不在时给界面用：装没装、载没载入、被没被系统关掉、上次怎么退出的、日志末尾、端口被谁占着。
pub fn service_status() -> Value {
    let (loaded, print) = launchctl(&["print", &target()]);
    let field = |key: &str| {
        print.lines().find_map(|l| l.trim().strip_prefix(key).map(|v| v.trim_start_matches([' ', '=']).trim().to_string()))
    };
    let (_, disabled_out) = launchctl(&["print-disabled", &domain()]);
    let disabled = disabled_out.lines().any(|l| l.contains(&format!("\"{}\"", label())) && l.contains("disabled"));
    let log = crate::logfile::latest().and_then(|p| std::fs::read_to_string(p).ok()).unwrap_or_default();
    let tail: Vec<&str> = log.lines().rev().take(30).collect::<Vec<_>>().into_iter().rev().collect();
    let port = crate::config::load_port();
    json!({
        "installed": plist_path().exists(),
        "loaded": loaded,
        "disabled": disabled,
        "pid": field("pid").and_then(|v| v.parse::<u64>().ok()),
        "lastExitCode": field("last exit code").and_then(|v| v.parse::<i64>().ok()),
        "label": label(),
        "bundledVersion": crate::VERSION,
        "logTail": tail,
        "port": port,
        "portOwner": super::port_owner(port),
    })
}

fn read_runtime() -> Option<Value> {
    serde_json::from_slice(&std::fs::read(paths::runtime()).ok()?).ok()
}

fn read_runtime_pid() -> Option<u32> {
    read_runtime()?.get("pid")?.as_u64().map(|p| p as u32)
}
