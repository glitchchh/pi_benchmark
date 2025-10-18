#!/bin/bash

echo "======================================================"
echo "  Raspberry Pi Comprehensive Benchmark by Glitchchh"
echo "======================================================"
echo "Start time: $(date)"
echo ""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' 

section() {
    echo -e "\n${BLUE}=== $1 ===${NC}"
    echo "----------------------------------------"
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${YELLOW}Warning: $1 not found. Installing...${NC}"
        sudo apt install -y $2
    fi
}

monitor_stats() {
    if command -v vcgencmd &> /dev/null; then
        local temp=$(vcgencmd measure_temp | cut -d= -f2)
        local throttled=$(vcgencmd get_throttled)
        local freq=$(vcgencmd measure_clock arm | awk -F= '{printf "%.0f MHz", $2/1000000}')
        echo -e "Temp: $temp | Freq: $freq | Throttled: $throttled"
    fi
}

section "Installing Required Tools"
sudo apt update
check_command sysbench sysbench
check_command stress stress
check_command stress-ng stress-ng
check_command hdparm hdparm
check_command memtester memtester

section "Initial System Status"
echo "Hostname: $(hostname)"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime -p)"
echo "Memory: $(free -h | grep Mem: | awk '{print $2}') total"
monitor_stats

section "CPU Information"
echo "Processor: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
echo "Cores: $(nproc)"
echo "Architecture: $(arch)"

section "Extended CPU Benchmark (5 minutes)"

echo -e "${YELLOW}Test 1: Single-threaded CPU performance (60 seconds)${NC}"
sysbench cpu --cpu-max-prime=100000 --threads=1 --time=60 run

echo -e "\n${YELLOW}Test 2: Multi-threaded CPU performance (60 seconds)${NC}"
sysbench cpu --cpu-max-prime=100000 --threads=$(nproc) --time=60 run

echo -e "\n${YELLOW}Test 3: CPU stress test with stress-ng (120 seconds)${NC}"
monitor_stats
stress-ng --cpu $(nproc) --matrix 1 --matrix-size 64 --vm 1 --vm-bytes 512M --timeout 120s --metrics-brief
monitor_stats

section "Extended Memory Benchmark"

echo -e "${YELLOW}Test 1: Memory speed test (2GB total)${NC}"
sysbench memory --memory-total-size=2G --memory-block-size=1M --memory-oper=write run

echo -e "\n${YELLOW}Test 2: Memory access patterns${NC}"
sysbench memory --memory-total-size=2G --memory-block-size=4K --memory-access-mode=rnd run

echo -e "\n${YELLOW}Test 3: Memtester (testing 512MB, 2 passes)${NC}"
if command -v memtester &> /dev/null; then
    AVAILABLE_MEM=$(free -m | grep Mem: | awk '{print $7}')
    TEST_MEM=$((AVAILABLE_MEM / 4))
    if [ $TEST_MEM -gt 512 ]; then
        TEST_MEM=512
    fi
    echo "Testing ${TEST_MEM}MB of RAM (2 passes)"
    memtester ${TEST_MEM}M 2
else
    echo "memtester not available, skipping"
fi

section "Storage I/O Benchmark"

echo -e "${YELLOW}Test 1: Sequential write speed${NC}"
dd if=/dev/zero of=./testfile_sequential bs=1M count=1024 oflag=direct status=progress 2>&1

echo -e "\n${YELLOW}Test 2: Sequential read speed${NC}"
dd if=./testfile_sequential of=/dev/null bs=1M status=progress 2>&1

echo -e "\n${YELLOW}Test 3: Random I/O with sysbench${NC}"
sysbench fileio --file-total-size=2G --file-test-mode=rndrw --time=120 --max-requests=0 prepare
sysbench fileio --file-total-size=2G --file-test-mode=rndrw --time=120 --max-requests=0 run
sysbench fileio --file-total-size=2G --file-test-mode=rndrw --time=120 --max-requests=0 cleanup

rm -f ./testfile_sequential

echo -e "\n${YELLOW}Test 4: HDPARM disk read${NC}"
if [ -b "/dev/mmcblk0" ]; then
    sudo hdparm -Tt /dev/mmcblk0
elif [ -b "/dev/sda" ]; then
    sudo hdparm -Tt /dev/sda
else
    echo "No block device found for hdparm test"
fi

section "Complete System Stress Test (3 minutes)"
echo -e "${YELLOW}Stressing CPU, memory, and I/O simultaneously${NC}"
echo "Starting at: $(date)"
monitor_stats

stress-ng --cpu $(nproc) --vm 2 --vm-bytes 1G --io 2 --hdd 1 --timeout 180s --metrics-brief

echo "Finished at: $(date)"
monitor_stats

section "Final System Status"
echo "End time: $(date)"
echo "Total benchmark duration: ~15-20 minutes"
monitor_stats

if command -v vcgencmd &> /dev/null; then
    section "Throttling Analysis"
    THROTTLED=$(vcgencmd get_throttled | cut -d= -f2)
    THROTTLED_DEC=$((16

    if [ $THROTTLED_DEC -eq 0 ]; then
        echo -e "${GREEN}No throttling detected${NC}"
    else
        echo -e "${RED}Throttling events detected:${NC}"
        [ $((THROTTLED_DEC & 0x1)) -ne 0 ] && echo "- Under-voltage detected"
        [ $((THROTTLED_DEC & 0x2)) -ne 0 ] && echo "- ARM frequency capped"
        [ $((THROTTLED_DEC & 0x4)) -ne 0 ] && echo "- Currently throttled"
        [ $((THROTTLED_DEC & 0x8)) -ne 0 ] && echo "- Soft temperature limit active"
    fi
fi

section "Benchmark Complete"
echo -e "${GREEN}Comprehensive benchmark finished!${NC}"
echo "Check the results above for performance metrics and any throttling issues."
echo "======================================================"
