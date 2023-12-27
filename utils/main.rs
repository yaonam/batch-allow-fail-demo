struct Execution {
    should_fail: bool,
}

enum ExecutionBoxed {
    Executions(Vec<Box<ExecutionBoxed>>),
    Execution { exec: Execution },
}

fn main() {
    let execs = ExecutionBoxed::Executions(vec![Box::new(ExecutionBoxed::Execution {
        exec: Execution { should_fail: false },
    })]);
}
