use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
    let agent_dir = PathBuf::from("ym-agent");
    let jar_path = out_dir.join("ym-agent.jar");

    let src_dir = agent_dir.join("src/main/java");
    let manifest = agent_dir.join("src/main/resources/META-INF/MANIFEST.MF");
    let classes_dir = out_dir.join("agent-classes");

    std::fs::create_dir_all(&classes_dir).expect("failed to create agent-classes dir");

    // Collect .java source files
    let sources: Vec<PathBuf> = walkdir(src_dir)
        .into_iter()
        .filter(|p| p.extension().is_some_and(|e| e == "java"))
        .collect();

    if sources.is_empty() {
        panic!("no .java files found in ym-agent/src/main/java");
    }

    // javac
    let mut javac = Command::new("javac");
    javac
        .arg("-d")
        .arg(&classes_dir)
        .arg("-source")
        .arg("11")
        .arg("-target")
        .arg("11");
    for src in &sources {
        javac.arg(src);
    }
    let status = javac.status().expect("failed to run javac — is JDK installed?");
    assert!(status.success(), "javac failed to compile ym-agent");

    // jar
    let status = Command::new("jar")
        .arg("cfm")
        .arg(&jar_path)
        .arg(&manifest)
        .arg("-C")
        .arg(&classes_dir)
        .arg(".")
        .status()
        .expect("failed to run jar");
    assert!(status.success(), "jar failed to package ym-agent");

    // No rerun-if-changed — always rebuild ym-agent (<1s, only 2 Java files)
}

fn walkdir(dir: PathBuf) -> Vec<PathBuf> {
    let mut result = Vec::new();
    if let Ok(entries) = std::fs::read_dir(&dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                result.extend(walkdir(path));
            } else {
                result.push(path);
            }
        }
    }
    result
}
