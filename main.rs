use ethers::{
    contract::{abigen, ContractFactory},
    core::utils::Anvil,
    middleware::SignerMiddleware,
    providers::{Http, Provider},
    signers::{LocalWallet, Signer},
    types::U256,
    utils::hex,
};
use ethers_solc::{Artifact, Project, ProjectPathsConfig};
use eyre::Result;
use serde::{Deserialize, Serialize};
use std::{path::PathBuf, sync::Arc, time::Duration, vec};

#[derive(Serialize, Deserialize)]
struct Exec {
    fail: bool,
    allow_fail: bool,
}

#[derive(Serialize, Deserialize)]
struct Batch {
    execs: Vec<Box<ExecBoxed>>,
    allow_fail: bool,
}

#[derive(Serialize, Deserialize)]
#[serde(untagged)]
enum ExecBoxed {
    Batch { batch: Batch },
    Exec { exec: Exec },
}

fn get_calldata<T>(
    callee_contract: Callee<T>,
    bitmap_contract: BytesErrorBitmap<T>,
) -> Vec<AllowFailedExecution> {
    // CREATE EXECUTION TREE HERE ----------------------------------------------
    let execs = vec![Box::new(ExecBoxed::Batch {
        batch: Batch {
            execs: vec![
                Box::new(ExecBoxed::Exec {
                    exec: Exec {
                        fail: true,
                        allow_fail: true,
                    },
                }),
                Box::new(ExecBoxed::Exec {
                    exec: Exec {
                        fail: false,
                        allow_fail: true,
                    },
                }),
            ],
            allow_fail: true,
        },
    })];

    println!(
        "Execution tree: {}",
        serde_json::to_string_pretty(&execs).unwrap()
    );

    // Encode the calldata
    return encode_execs(callee_contract.clone(), bitmap_contract.clone(), execs);
}

fn encode_execs<T>(
    callee_contract: Callee<T>,
    bitmap_contract: BytesErrorBitmap<T>,
    execs: Vec<Box<ExecBoxed>>,
) -> Vec<AllowFailedExecution> {
    execs
        .into_iter()
        .map(|exec_boxed| match *exec_boxed {
            ExecBoxed::Batch { batch } => AllowFailedExecution {
                execution: Execution {
                    target: bitmap_contract.address(),
                    value: 0.into(),
                    call_data: bitmap_contract
                        .encode(
                            "_batchExeAllowFail",
                            (encode_execs(
                                callee_contract.clone(),
                                bitmap_contract.clone(),
                                batch.execs,
                            ),),
                        )
                        .unwrap(),
                },
                allow_failed: batch.allow_fail,
                operation: 0,
            },
            ExecBoxed::Exec { exec } => AllowFailedExecution {
                execution: Execution {
                    target: callee_contract.address(),
                    value: 0.into(),
                    call_data: callee_contract.encode("foo", (exec.fail,)).unwrap(),
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
    "./out/BytesErrorBitmap.sol/Callee.json",
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
    let callee_contract = Callee::new(callee_addr, client.clone());
    let bitmap_contract = BytesErrorBitmap::new(bitmap_addr, client.clone());

    // 9. call the `setValue` method
    // (first `await` returns a PendingTransaction, second one waits for it to be mined)
    let _receipt = bitmap_contract
        .batch_exe_allow_fail(get_calldata(
            callee_contract.clone(),
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

    // Get the bitmap
    println!("Emitted bitmap: {}", logs[0].bitmap);

    // Convert counter and bitmap to u128
    let counter: String = hex::encode(&logs[0].bitmap)[0..64].to_string();
    let counter = u8::from_str_radix(&counter, 16)?;
    let bitmap: String = hex::encode(&logs[0].bitmap)[64..].to_string();
    let bitmap = U256::from_str_radix(&bitmap, 16)?;

    println!("Counter: {}", counter);
    println!("Bitmap: {}", bitmap);

    // Decode the bitmap
    let (execs, _) = decode_bitmap(
        vec![Box::new(ExecBoxed::Batch {
            batch: Batch {
                execs: vec![Box::new(ExecBoxed::Exec {
                    exec: Exec {
                        fail: true,
                        allow_fail: true,
                    },
                })],
                allow_fail: true,
            },
        })],
        counter,
        bitmap,
        0,
    );

    println!(
        "Decoded execution tree: {}",
        serde_json::to_string_pretty(&execs).unwrap()
    );

    Ok(())
}

#[derive(Serialize, Deserialize)]
struct ExecResult {
    fail: bool,
    allow_fail: bool,
    failed: bool,
}

#[derive(Serialize, Deserialize)]
struct BatchResult {
    execs: Vec<Box<ExecResultBoxed>>,
    allow_fail: bool,
    failed: bool,
}

#[derive(Serialize, Deserialize)]
#[serde(untagged)]
enum ExecResultBoxed {
    BatchResult { batch_result: BatchResult },
    ExecResult { exec_result: ExecResult },
}

fn decode_bitmap(
    execs: Vec<Box<ExecBoxed>>,
    counter: u8,
    bitmap: U256,
    i: u8,
) -> (Vec<Box<ExecResultBoxed>>, u8) {
    let mut _i: u8 = i;
    let mut reverted: bool = false;
    let _execs = execs
        .into_iter()
        .map(|exec_boxed| match *exec_boxed {
            ExecBoxed::Batch { batch } => Box::new(ExecResultBoxed::BatchResult {
                batch_result: {
                    let __execs: Vec<Box<ExecResultBoxed>>;
                    (__execs, _i) = decode_bitmap(batch.execs, counter, bitmap, _i);
                    let failed = bitmap.bit((255 - _i).into());
                    reverted = reverted || (failed && !batch.allow_fail);
                    let res = BatchResult {
                        execs: __execs,
                        allow_fail: batch.allow_fail,
                        failed: failed,
                    };
                    if !reverted {
                        _i += 1;
                    };
                    res
                },
            }),
            ExecBoxed::Exec { exec } => Box::new(ExecResultBoxed::ExecResult {
                exec_result: {
                    let res = ExecResult {
                        fail: bitmap.bit(i.into()),
                        allow_fail: exec.allow_fail,
                        failed: bitmap.bit((255 - i).into()),
                    };
                    if !reverted {
                        _i += 1;
                    };
                    res
                },
            }),
        })
        .collect();
    return (_execs, _i);

    // if batch, recurse
    // if batch revert, set rest to fail (don't increment)
    // set current execution result
    // return results and incremented counter

    // if i == counter, set all to fail

    // if reverted, iterate all and set to fail
}
