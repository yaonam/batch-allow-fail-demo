use ethers::{
    contract::{abigen, ContractFactory, ContractInstance},
    core::utils::Anvil,
    middleware::SignerMiddleware,
    providers::{Http, Middleware, Provider},
    signers::{LocalWallet, Signer},
    types::H160,
    // solc::{Artifact, Project, ProjectPathsConfig},
};
use ethers_solc::{Artifact, Project, ProjectPathsConfig};
use eyre::Result;
use serde::{Deserialize, Serialize};
use std::{borrow::Borrow, path::PathBuf, sync::Arc, time::Duration, vec};

#[derive(Serialize, Deserialize)]
struct Exec {
    fail: bool,
    allow_fail: bool,
}

#[derive(Serialize, Deserialize)]
#[serde(untagged)]
enum ExecBoxed {
    Execs(Vec<Box<ExecBoxed>>),
    Exec { exec: Exec },
}

fn get_calldata<T, U, V>(
    callee_contract: ContractInstance<T, U>,
    callee_addr: H160,
    bitmap_contract: BytesErrorBitmap<V>,
) -> Vec<AllowFailedExecution>
where
    T: Borrow<U>,
    T: Clone,
{
    let execs = vec![Box::new(ExecBoxed::Execs(vec![Box::new(
        ExecBoxed::Exec {
            exec: Exec {
                fail: false,
                allow_fail: true,
            },
        },
    )]))];

    println!("{}", serde_json::to_string_pretty(&execs).unwrap());

    // Encode the calldata
    return encode_execs(
        callee_contract.clone(),
        callee_addr,
        bitmap_contract.clone(),
        execs,
    );
}

fn encode_execs<T, U, V>(
    callee_contract: ContractInstance<T, U>,
    callee_addr: H160,
    bitmap_contract: BytesErrorBitmap<V>,
    execs: Vec<Box<ExecBoxed>>,
) -> Vec<AllowFailedExecution>
where
    T: Borrow<U>,
    T: Clone,
{
    execs
        .into_iter()
        .map(|exec_boxed| match *exec_boxed {
            ExecBoxed::Execs(_execs) => AllowFailedExecution {
                execution: Execution {
                    target: bitmap_contract.address(),
                    value: 0.into(),
                    call_data: bitmap_contract
                        .encode(
                            "_batchExeAllowFail",
                            (encode_execs(
                                callee_contract.clone(),
                                callee_addr,
                                bitmap_contract.clone(),
                                _execs,
                            ),),
                        )
                        .unwrap(),
                },
                allow_failed: true,
                operation: 0,
            },
            ExecBoxed::Exec { exec } => AllowFailedExecution {
                execution: Execution {
                    target: callee_addr,
                    value: 0.into(),
                    call_data: callee_contract.encode("ShouldFail", (exec.fail,)).unwrap(),
                },
                allow_failed: exec.allow_fail,
                operation: 0,
            },
        })
        .collect()
}

// Generate the type-safe contract bindings by providing the ABI
abigen!(
    BytesErrorBitmap,
    "./out/BytesErrorBitmap.sol/BytesErrorBitmap.json",
    event_derives(serde::Deserialize, serde::Serialize);
    Callee,
    "./out/BytesErrorBitmap.sol/BytesErrorBitmap.json",
);

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
    let callee_contract = output
        .find_first("Callee")
        .expect("could not find Callee contract")
        .clone();
    let (callee_abi, callee_bytecode, _) = callee_contract.into_parts();
    let bitmap_contract = output
        .find_first("BytesErrorBitmap")
        .expect("could not find BytesErrorBitmap contract")
        .clone();
    let (bitmap_abi, bitmap_bytecode, _) = bitmap_contract.into_parts();

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
    let callee_factory = ContractFactory::new(
        callee_abi.unwrap(),
        callee_bytecode.unwrap(),
        client.clone(),
    );
    let bitmap_factory = ContractFactory::new(
        bitmap_abi.unwrap(),
        bitmap_bytecode.unwrap(),
        client.clone(),
    );

    // 6. deploy it with the constructor arguments
    let callee_contract = callee_factory.deploy(())?.send().await?;
    let bitmap_contract = bitmap_factory.deploy(())?.send().await?;

    // 7. get the contract's address
    let callee_addr = callee_contract.address();
    let bitmap_addr = bitmap_contract.address();
    println!("Deployed Callee to: {}", callee_addr);
    println!("Deployed BytesErrorBitmap to: {}", bitmap_addr);

    // 8. instantiate the contract
    Callee::new(callee_addr, client.clone());
    let bitmap_contract = BytesErrorBitmap::new(bitmap_addr, client.clone());

    println!(
        "{}",
        serde_json::to_string_pretty(&get_calldata(
            callee_contract.clone(),
            callee_addr,
            bitmap_contract.clone(),
        ))
        .unwrap()
    );

    // 9. call the `setValue` method
    // (first `await` returns a PendingTransaction, second one waits for it to be mined)
    let _receipt = bitmap_contract
        .batch_exe_allow_fail(get_calldata(
            callee_contract.clone(),
            callee_addr,
            bitmap_contract.clone(),
        ))
        .send()
        .await?
        .await?;

    // 10. get all events
    let logs = bitmap_contract
        .bitmap_error_filter()
        .from_block(0u64)
        .query()
        .await?;

    // // 11. get the new value
    // let value = contract.get_value().call().await?;

    // println!("Value: {value}. Logs: {}", serde_json::to_string(&logs)?);
    println!("Logs: {}", serde_json::to_string(&logs)?);

    Ok(())
}
