import subprocess
import re
import os
import shutil
import time
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

SERVER_JAR = "fabric-server-mc.1.21.10-loader.0.17.3-launcher.1.1.0.jar"
WORLD_FOLDER = os.path.join(SCRIPT_DIR, "world")

# Haha this is funny number of 666c
CHUNKY_RADIUS = 10656

JAVA_PATHS = {
    "/usr/lib/jvm/java-25-graalvm/bin/java": "graalvm-java",
    "/usr/lib/jvm/java-25-openjdk/bin/java": "openjdk-java",
    "/usr/lib/jvm/jre-jetbrains/bin/java": "jetbrains-java",
    "/usr/lib/jvm/java-25-temurin/bin/java": "temurin-java"
}

USER_JVM_ARGS = [
    "89th_user_jvm_args.txt",
    "small_user_jvm_args.txt",
    "atm_user_jvm_args.txt",
    "aikar_user_jvm_args.txt",
    "velocity_user_jvm_args.txt",
    "none_user_jvm_args.txt"
]

DIMENSION_PATTERN = [
    r"Compiled program for minecraft:the_nether for device",
    r"Compiled program for minecraft:the_end for device"
]

CHUNKY_RADIUS_PATTERN = rf"Radius changed to {CHUNKY_RADIUS}\."
STOP_PATTERN = r"Task finished for minecraft:overworld\."

BENCHMARK_DIR = os.path.join(SCRIPT_DIR, "benchmarks")
os.makedirs(BENCHMARK_DIR, exist_ok=True)

CHUNKY_TASKS_FOLDER = os.path.join(SCRIPT_DIR, "config", "chunky", "tasks")

PROFILING_SCRIPTS = [
    "log_cpumem.sh",
    "log_disk.sh",
    "log_gpu.sh"
]
PROFILING_FOLDER = os.path.join(SCRIPT_DIR, "profiling")
profiling_processes = []


def clear_folder(folder_path):
    if os.path.exists(folder_path):
        print(f"Clearing folder: {folder_path}")
        shutil.rmtree(folder_path)
    os.makedirs(folder_path, exist_ok=True)


def start_profiling_scripts():
    for script in PROFILING_SCRIPTS:
        script_path = os.path.join(PROFILING_FOLDER, script)
        if os.path.exists(script_path):
            print(f"Starting profiling script: {script}")
            proc = subprocess.Popen(
                ["bash", script_path],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            profiling_processes.append(proc)
        else:
            print(f"Script not found: {script_path}")


def stop_profiling_scripts():
    for proc in profiling_processes:
        print(f"Stopping profiling script PID={proc.pid}...")
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            print("Force killing profiling script...")
            proc.kill()


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


def delete_chunky_tasks():
    if os.path.exists(CHUNKY_TASKS_FOLDER):
        print(f"Deleting Chunky tasks folder: {CHUNKY_TASKS_FOLDER}")
        shutil.rmtree(CHUNKY_TASKS_FOLDER)


def run_benchmark(java_path, jvm_args_file, identifier, run_number):
    delete_world()
    delete_chunky_tasks()

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_filename = f"benchmark_{identifier}_{jvm_args_file}_run{run_number}_{timestamp}.log"
    log_path = os.path.join(BENCHMARK_DIR, log_filename)

    print(f"\n==== Running benchmark ====")
    print(
        f"Run {run_number}: Java: {java_path} ({identifier}), JVM args: {jvm_args_file}")
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
        send_input(process, f"chunky radius {CHUNKY_RADIUS}", logfile)
        wait_for_pattern(process, CHUNKY_RADIUS_PATTERN, logfile)
        send_input(process, "chunky start", logfile)

        regex_stop = re.compile(STOP_PATTERN)
        last_health_time = 0
        while True:
            line = process.stdout.readline().decode(errors="ignore")
            if line:
                line_clean = line.strip()
                print(line_clean)
                logfile.write(line)
                logfile.flush()
                if regex_stop.search(line_clean):
                    print("Task finished detected, stopping server...")
                    send_input(process, "stop", logfile)
                    break

            now = time.time()
            if now - last_health_time >= 5:
                send_input(process, "spark healthreport", logfile)
                last_health_time = now

        process.wait()
        print("Server stopped.")


clear_folder(BENCHMARK_DIR)
clear_folder(CHUNKY_TASKS_FOLDER)
start_profiling_scripts()

try:
    for java_path, identifier in JAVA_PATHS.items():
        for jvm_args_file in USER_JVM_ARGS:
            for run_number in range(1, 5):
                run_benchmark(java_path, jvm_args_file, identifier, run_number)
                time.sleep(5)
finally:
    stop_profiling_scripts()

print("\nAll benchmarks completed.")
