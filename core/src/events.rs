//! 给控制接口（界面）的事件总线。只说"谁变了"，发送时再读当前状态，所以积压了也不会推出旧数据。

use serde_json::Value;
use tokio::sync::broadcast;

#[derive(Clone, Debug)]
pub enum Event {
    Core,
    Mcp(String),
    Services,
    Calls(Vec<Value>),
    Memory(Value),
    /// 整体变了（导入、重新读取配置）：界面重新拿一份完整快照。
    Snapshot,
}

#[derive(Clone)]
pub struct Events(broadcast::Sender<Event>);

impl Events {
    pub fn new() -> Self {
        Self(broadcast::channel(1024).0)
    }
    pub fn emit(&self, e: Event) {
        let _ = self.0.send(e);
    }
    pub fn subscribe(&self) -> broadcast::Receiver<Event> {
        self.0.subscribe()
    }
    pub fn has_subscribers(&self) -> bool {
        self.0.receiver_count() > 0
    }
}
