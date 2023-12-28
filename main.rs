// use serde::{Deserialize, Serialize};

// #[derive(Serialize, Deserialize)]
// struct Execution {
//     should_fail: bool,
// }

// #[derive(Serialize, Deserialize)]
// #[serde(untagged)]
// enum ExecutionBoxed {
//     Executions(Vec<Box<ExecutionBoxed>>),
//     Execution { exec: Execution },
// }

// fn main() {
//     let execs = ExecutionBoxed::Executions(vec![Box::new(ExecutionBoxed::Execution {
//         exec: Execution { should_fail: false },
//     })]);

//     println!("{}", serde_json::to_string_pretty(&execs).unwrap());
// }

use ethers::{
    contract::{abigen, ContractFactory},
    core::utils::Anvil,
    middleware::SignerMiddleware,
    providers::{Http, Middleware, Provider},
    signers::{LocalWallet, Signer},
    // solc::{Artifact, Project, ProjectPathsConfig},
};
use ethers_solc::{Artifact, Project, ProjectPathsConfig};
use eyre::Result;
use std::{path::PathBuf, sync::Arc, time::Duration, vec};

// Generate the type-safe contract bindings by providing the ABI
abigen!(
    BytesErrorBitmap,
    "./out/BytesErrorBitmap.sol/BytesErrorBitmap.json"
);
// abigen!(
//     Operation,
//     "./out/BytesErrorBitmap.sol/BytesErrorBitmap.json"
// );
// abigen!(
//     Execution,
//     "./out/BytesErrorBitmap.sol/BytesErrorBitmap.json"
// );
// abigen!(
//     AllowFailedExecution,
//     "./out/BytesErrorBitmap.sol/BytesErrorBitmap.json"
// );

#[tokio::main]
async fn main() -> Result<()> {
    // the directory we use is root-dir/examples
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("src");
    // we use `root` for both the project root and for where to search for contracts since
    // everything is in the same directory
    let paths = ProjectPathsConfig::builder()
        .root(&root)
        .sources(&root)
        .build()
        .unwrap();

    // get the solc project instance using the paths above
    let project = Project::builder()
        .paths(paths)
        .ephemeral()
        .no_artifacts()
        .build()
        .unwrap();
    // compile the project and get the artifacts
    let output = project.compile().unwrap();
    let contract = output
        .find_first("Callee")
        .expect("could not find contract")
        .clone();
    let (abi, bytecode, _) = contract.into_parts();

    // 2. instantiate our wallet & anvil
    let anvil = Anvil::new().spawn();
    let wallet: LocalWallet = anvil.keys()[0].clone().into();

    // 3. connect to the network
    let provider =
        Provider::<Http>::try_from(anvil.endpoint())?.interval(Duration::from_millis(10u64));

    // 4. instantiate the client with the wallet
    let client = SignerMiddleware::new(provider, wallet.with_chain_id(anvil.chain_id()));
    let client = Arc::new(client);

    // 5. create a factory which will be used to deploy instances of the contract
    let factory = ContractFactory::new(abi.unwrap(), bytecode.unwrap(), client.clone());

    // 6. deploy it with the constructor arguments
    let deployment = factory.deploy(())?;
    let sending = deployment.send();
    let contract = sending.await?;

    // 7. get the contract's address
    let addr = contract.address();

    // 8. instantiate the contract
    let contract = BytesErrorBitmap::new(addr, client.clone());

    // 8.5 build calldata
    let exec = Execution {
        target: addr,
        value: 0.into(),
        call_data: ethers::types::Bytes::new(),
    };
    let allow_fail_exec = AllowFailedExecution {
        execution: exec,
        allow_failed: false,
        operation: 0,
    };

    // 9. call the `setValue` method
    // (first `await` returns a PendingTransaction, second one waits for it to be mined)
    let _receipt = contract
        .batch_exe_allow_fail(vec![allow_fail_exec])
        .send()
        .await?
        .await?;

    // // 10. get all events
    // let logs = contract
    //     .value_changed_filter()
    //     .from_block(0u64)
    //     .query()
    //     .await?;

    // // 11. get the new value
    // let value = contract.get_value().call().await?;

    // println!("Value: {value}. Logs: {}", serde_json::to_string(&logs)?);

    Ok(())
}
