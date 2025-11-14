import subprocess
import re
import os
import shutil
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

SERVER_JAR = "fabric-server-mc.1.21.10-loader.0.17.3-launcher.1.1.0.jar"
WORLD_FOLDER = os.path.join(SCRIPT_DIR, "world")

JAVA_PATHS = {
    "/usr/lib/jvm/java-25-graalvm/bin/java": "graalvm-java",
    "/usr/lib/jvm/java-25-openjdk/bin/java": "openjdk-java",
    "/usr/lib/jvm/jre-jetbrains/bin/java": "jetbrains-java",
    "/usr/lib/jvm/java-25-temurin/bin/java": "temurin-java"
}

USER_JVM_ARGS = [
    "89th_user_jvm_args",
    "small_user_jvm_args",
    "atm_user_jvm_args.txt",
    "aikar_user_jvm_args.txt",
    "velocity_user_jvm_args.txt",
    "none_user_jvm_args.txt"
]

DIMENSION_PATTERN = [
    r"Compiled program for minecraft:the_nether for device",
    r"Compiled program for minecraft:the_end for device"
]

CHUNKY_RADIUS_PATTERN = r"Radius changed to 1000\."
STOP_PATTERN = r"Task finished for minecraft:overworld\."

BENCHMARK_DIR = os.path.join(SCRIPT_DIR, "benchmarks")
os.makedirs(BENCHMARK_DIR, exist_ok=True)


def wait_for_pattern(process, pattern, logfile):
    regex = re.compile(pattern)
    while True:
        line = process.stdout.readline().decode(errors="ignore")
        if line:
            line_clean = line.strip()
            print(line_clean)
            logfile.write(line)
            logfile.flush()
            if regex.search(line_clean):
                return line_clean


def wait_for_all_patterns(process, patterns, logfile):
    patterns_remaining = set(patterns)
    regexes = {p: re.compile(p) for p in patterns}

    while patterns_remaining:
        line = process.stdout.readline().decode(errors="ignore")
        if line:
            line_clean = line.strip()
            print(line_clean)
            logfile.write(line)
            logfile.flush()
            for pattern in list(patterns_remaining):
                if regexes[pattern].search(line_clean):
                    print(f"Detected: {pattern}")
                    patterns_remaining.remove(pattern)


def send_input(process, command, logfile):
    logfile.write(f"> {command}\n")
    logfile.flush()
    process.stdin.write((command + "\n").encode())
    process.stdin.flush()


def delete_world():
    if os.path.exists(WORLD_FOLDER):
        print(f"Deleting world folder: {WORLD_FOLDER}")
        shutil.rmtree(WORLD_FOLDER)


delete_world()


def run_benchmark(java_path, jvm_args_file, identifier):
    delete_world()
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_filename = f"benchmark_{identifier}_{jvm_args_file}_{timestamp}.log"
    log_path = os.path.join(BENCHMARK_DIR, log_filename)

    print(f"\n==== Running benchmark ====")
    print(f"Java: {java_path} ({identifier}), JVM args: {jvm_args_file}")
    print(f"Logging to: {log_path}")

    jar_file = os.path.join(SCRIPT_DIR, SERVER_JAR)
    jvm_args_path = os.path.join(SCRIPT_DIR, jvm_args_file)
    cmd = [java_path]
    if os.path.exists(jvm_args_path):
        cmd.append(f"@{jvm_args_path}")
    cmd += ["-jar", jar_file, "nogui"]

    with open(log_path, "w") as logfile:
        process = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=1
        )

        wait_for_pattern(process, r"Done \([0-9.]+s\)!", logfile)
        wait_for_all_patterns(process, DIMENSION_PATTERN, logfile)
        send_input(process, "chunky radius 1000", logfile)
        wait_for_pattern(process, CHUNKY_RADIUS_PATTERN, logfile)
        send_input(process, "chunky start", logfile)
        wait_for_pattern(process, STOP_PATTERN, logfile)
        print("Task finished detected, stopping server...")
        send_input(process, "stop", logfile)
        process.wait()
        print("Server stopped.")


for java_path, identifier in JAVA_PATHS.items():
    for jvm_args_file in USER_JVM_ARGS:
        run_benchmark(java_path, jvm_args_file, identifier)

print("\nAll benchmarks completed.")
