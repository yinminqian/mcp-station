//! MCP Station 内核（mcp-core）：本机常驻的 MCP 网关。托管所有 MCP（每个只跑一份），客户端都连同一个地址；
//! 界面（Mac 的 Swift App，以后的 Windows 界面）通过控制接口管理它。从 mcp-rust（多用户网关）复制后改造，见 docs/ARCHITECTURE.md §3。
//!
//! 用法：
//!   mcp-core [run]          前台运行（LaunchAgent 就是这么跑的）
//!   mcp-core install [--restart]   安装 / 升级开机自启并确保在跑，输出一行 JSON
//!   mcp-core uninstall      撤掉开机自启（数据保留）
//!   mcp-core status         给界面用：装没装、在不在跑、日志末尾、端口被谁占着
//!   mcp-core --version

mod calls;
mod children;
mod config;
mod control;
mod error;
mod events;
mod jsonrpc;
mod logfile;
mod northbound;
mod paths;
mod platform;
mod registry;
mod router;
mod runtime;
mod upstream;

use std::process::ExitCode;

/// 版本号：打包时由 scripts/build-app.sh 从仓库根目录的 VERSION 传进来（和 App 一致），单独 cargo build 时用 Cargo.toml 里的。
/// App 更新后发现正在跑的内核版本和包里带的不一样，就自动升级内核。
pub const VERSION: &str = match option_env!("MCPSTATION_VERSION") {
    Some(v) => v,
    None => env!("CARGO_PKG_VERSION"),
};
use std::time::Duration;
use tokio_util::sync::CancellationToken;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let print = |r: Result<serde_json::Value, String>| match r {
        Ok(v) => {
            println!("{v}");
            ExitCode::SUCCESS
        }
        Err(e) => {
            println!("{}", serde_json::json!({ "ok": false, "error": e }));
            ExitCode::FAILURE
        }
    };
    match args.first().map(String::as_str).unwrap_or("run") {
        "--version" | "version" => {
            println!("mcp-core {} (api {})", crate::VERSION, control::API_VERSION);
            ExitCode::SUCCESS
        }
        "install" => print(platform::install(args.iter().any(|a| a == "--restart"))),
        "uninstall" => print(platform::uninstall()),
        "status" => print(Ok(platform::service_status())),
        "run" => run(),
        other => {
            eprintln!("不认识的命令 {other}。用法：mcp-core [run|install [--restart]|uninstall|status|--version]");
            ExitCode::from(2)
        }
    }
}

fn run() -> ExitCode {
    let _ = std::fs::create_dir_all(paths::logs_dir());
    // 单实例：拿不到锁说明已经有一个在跑，退出码 0（launchd 不会因此反复拉起）。
    let lock = match std::fs::OpenOptions::new().create(true).truncate(false).write(true).open(paths::lock()) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("打不开 {}：{e}", paths::lock().display());
            return ExitCode::FAILURE;
        }
    };
    if lock.try_lock().is_err() {
        eprintln!("已经有一个内核在跑了（{}）", paths::data_dir().display());
        return ExitCode::SUCCESS;
    }

    logfile::prune();
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::try_from_env("MCPSTATION_LOG").unwrap_or_else(|_| "info".into()))
        .with_ansi(false)
        .with_writer(logfile::Daily::default)
        .init();

    let rt = tokio::runtime::Builder::new_multi_thread().enable_all().build().expect("tokio");
    rt.block_on(serve());
    drop(lock);
    ExitCode::SUCCESS
}

async fn serve() {
    tracing::info!(version = crate::VERSION, dir = %paths::data_dir().display(), "内核启动");
    children::reap_stale();
    let loaded = config::load();
    if let Some(e) = &loaded.error {
        tracing::error!("配置文件读不了，用上一份能用的备份运行，并拒绝写入：{e}");
    }
    let login_path = platform::login_path().await;
    let shutdown = CancellationToken::new();
    let (reg, port_rx) = registry::Registry::new(loaded, login_path, shutdown.clone());

    // 控制接口：127.0.0.1 的随机端口，和令牌一起写进 runtime.json。
    let ctl = match tokio::net::TcpListener::bind(("127.0.0.1", 0)).await {
        Ok(l) => l,
        Err(e) => {
            tracing::error!("控制接口起不来：{e}");
            return;
        }
    };
    let control_port = ctl.local_addr().map(|a| a.port()).unwrap_or(0);
    let token = runtime::new_token();
    runtime::write(reg.config().port, control_port, &token, reg.started_at);
    let (stop, ctl_reg) = (shutdown.clone(), reg.clone());
    tokio::spawn(async move {
        let _ = axum::serve(ctl, control::app(ctl_reg, token)).with_graceful_shutdown(async move { stop.cancelled().await }).await;
    });
    tracing::info!(control_port, "控制接口开始监听");

    reg.reconcile();
    reg.spawn_memory_sampler();
    {
        let reg = reg.clone();
        tokio::spawn(async move {
            let mut tick = tokio::time::interval(Duration::from_secs(3600));
            tick.tick().await;
            loop {
                tick.tick().await;
                logfile::prune();
                reg.calls.prune();
            }
        });
    }
    let gateway = tokio::spawn(northbound::serve(reg.clone(), port_rx, shutdown.clone()));

    platform::shutdown_signal().await;
    tracing::info!("收到退出信号，关停");
    shutdown.cancel();
    let _ = tokio::time::timeout(Duration::from_secs(2), gateway).await;
    // 等各上游清理完子进程，最多 5 秒
    let deadline = std::time::Instant::now() + Duration::from_secs(5);
    while std::time::Instant::now() < deadline && std::fs::read(paths::children()).is_ok_and(|b| b.len() > 4) {
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    runtime::remove();
}
