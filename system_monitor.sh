#!/bin/bash
set -euo pipefail
trap 'echo "错误: 发生错误在行 $LINENO" >&2; exit 1' ERR
set -euo pipefail
trap 'echo "错误: 发生错误在行 $LINENO" >&2; exit 1' ERR
 
# Linux 综合系统监控脚本 v2.0 
# 监控 CPU/内存/磁盘/网络/进程/内核缓存 
# 整合 dstat/iotop/iftop/nethogs/slabtop/vmstat/iostat/mpstat/pidstat/sar 功能 
 
VERSION="2.0" 
INTERVAL=2 
COUNT=10 
REPORT_FILE="" 
 
# 颜色定义 
RED='\033[0;31m' 
GREEN='\033[0;32m' 
YELLOW='\033[1;33m' 
BLUE='\033[0;34m' 
CYAN='\033[0;36m' 
NC='\033[0m'# No Color 
 
print_banner() {
echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║ Linux 综合系统监控脚本 v${VERSION}          ║"
echo "║ 监控 CPU/内存/磁盘/网络/进程/内核缓存                 ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
}
 
print_usage() {
echo "用法:  $0 [选项] [模块]"
echo ""
echo "选项:"
echo " -i, --interval <秒> 采样间隔 (默认: 2秒)"
echo " -c, --count <次数> 采样次数 (默认: 10次)"
echo " -o, --output <文件> 输出报告到文件"
echo " -h, --help 显示此帮助"
echo ""
echo "模块:"
echo " cpu CPU监控 (对应: mpstat, vmstat)"
echo " memory 内存监控 (对应: vmstat, sar -r)"
echo " disk 磁盘I/O监控 (对应: iostat, iotop)"
echo " network 网络监控 (对应: iftop, nethogs)"
echo " process 进程监控 (对应: pidstat, dstat)"
echo " slab 内核缓存监控 (对应: slabtop)"
echo " overview 系统概览 (综合所有指标)"
echo " once 单次全检测"
echo ""
echo "示例:"
echo "  $0 cpu -i 1 -c 5 CPU监控, 1秒间隔, 5次采样"
echo "  $0 disk -o report.txt 磁盘监控, 输出到文件"
echo "  $0 once 单次全检测"
}
 
parse_args() {
while [[ $# -gt 0 ]]; do
case "$1" in
-i|--interval)
INTERVAL="$2"
shift 2
;;
-c|--count)
COUNT="$2"
shift 2
;;
-o|--output)
REPORT_FILE="$2"
shift 2
;;
-h|--help)
print_usage
exit 0
;;
-*)
echo "错误: 未知选项 $1"
print_usage
exit 1
;;
*)
MODULE="$1"
shift
;;
esac
done
}
 
print_separator() {
echo "+--------------------------------------------------------------------------------------+"
}
 
# 计算字符串的显示宽度（中文字符算2个宽度） 
str_width() {
local str="$1"
local bytes
local chars
local chinese
local width
bytes=$(printf '%s' "$str" | wc -c)
chars=${#str}
chinese=$(( (bytes - chars) / 2 ))
width=$(( chars + chinese ))
echo "$width"
}
 
# 格式化表格单元格，考虑中文宽度 
fmt_cell() {
local width="$1"
local str="$2"
local str_w
local pad
str_w=$(str_width "$str")
pad=$((width - str_w))
if [[ $pad -lt 0 ]]; then
pad=0
fi
printf "%s%*s" "$str" "$pad" ""
}
 
# 打印表格分隔线 
# 参数: 各列的宽度数组 
print_table_line() {
local widths=("$@")
local line="+"
local w
for w in "${widths[@]}"; do
local i
for ((i=0; i<w; i++)); do
line="${line}-"
done
line="${line}+"
done
echo "$line"
}
 
# 打印表格行 
# 参数: 宽度数组 值数组 
print_table_row() { 
    local -n widths_arr=$1 
    shift 
    local values=("$@") 
    local row="|" 
    local i 
    for ((i=0; i<${#values[@]}; i++)); do 
        local w=${widths_arr[$i]} 
        local v="${values[$i]}" 
        local cell=$(fmt_cell "$w""$v") 
        row="${row}${cell}|" 
    done 
    echo"$row" 
} 
 
print_header() {
printf "%-20s %-15s %-15s %-15s %-15s %-15s\n" "时间" "用户" "运行队列" "内存使用%" "CPU使用%" "负载"
}

check_command_exists() {
local cmd="$1"
if ! command -v "$cmd" >/dev/null 2>&1; then
echo "警告: 未找到命令 $cmd，相关功能可能受限" >&2
fi
}

validate_args() {
if [[ -n "${INTERVAL-}" ]]; then
if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]]; then
echo "错误: INTERVAL 必须为正整数" >&2
exit 1
fi
if (( INTERVAL <= 0 )); then
echo "错误: INTERVAL 必须大于0" >&2
exit 1
fi
fi
if [[ -n "${COUNT-}" ]]; then
if ! [[ "$COUNT" =~ ^[0-9]+$ ]]; then
echo "错误: COUNT 必须为正整数" >&2
exit 1
fi
if (( COUNT <= 0 )); then
echo "错误: COUNT 必须大于0" >&2
exit 1
fi
fi
}
 
monitor_cpu() { 
    print_banner 
    echo"【模块: CPU监控】" 
    echo"功能说明: 监控系统CPU使用率、运行队列长度、上下文切换次数" 
    echo"" 
    local cpu_widths=(28 7 7 7) 
    print_table_line "${cpu_widths[@]}" 
    print_table_row cpu_widths "时间""用户%""系统%""空闲%" 
    print_table_line "${cpu_widths[@]}" 
     
    local prev_stat=$(cat /proc/stat | grep "^cpu ") 
     
    for ((i=1; i<=COUNT; i++)); do 
        local curr_time=$(date +"%Y-%m-%d %H:%M:%S") 
        local curr_stat=$(cat /proc/stat | grep "^cpu ") 
         
        local prev_user=$(echo$prev_stat | awk '{print $2}') 
        local prev_nice=$(echo$prev_stat | awk '{print $3}') 
        local prev_system=$(echo$prev_stat | awk '{print $4}') 
        local prev_idle=$(echo$prev_stat | awk '{print $5}') 
        local prev_iowait=$(echo$prev_stat | awk '{print $6}') 
        local prev_irq=$(echo$prev_stat | awk '{print $7}') 
        local prev_softirq=$(echo$prev_stat | awk '{print $8}') 
         
        local curr_user=$(echo$curr_stat | awk '{print $2}') 
        local curr_nice=$(echo$curr_stat | awk '{print $3}') 
        local curr_system=$(echo$curr_stat | awk '{print $4}') 
        local curr_idle=$(echo$curr_stat | awk '{print $5}') 
        local curr_iowait=$(echo$curr_stat | awk '{print $6}') 
        local curr_irq=$(echo$curr_stat | awk '{print $7}') 
        local curr_softirq=$(echo$curr_stat | awk '{print $8}') 
         
        local user_delta=$((curr_user - prev_user)) 
        local nice_delta=$((curr_nice - prev_nice)) 
        local system_delta=$((curr_system - prev_system)) 
        local idle_delta=$((curr_idle - prev_idle)) 
        local iowait_delta=$((curr_iowait - prev_iowait)) 
        local irq_delta=$((curr_irq - prev_irq)) 
        local softirq_delta=$((curr_softirq - prev_softirq)) 
         
        local total_delta=$((user_delta + nice_delta + system_delta + idle_delta + iowait_delta + irq_delta + softirq_delta)) 
         
        local user_pct=0 
        local system_pct=0 
        local idle_pct=100 
        local iowait_pct=0 
        local irq_pct=0 
        local softirq_pct=0 
         
        if [[ $total_delta -gt 0 ]]; then 
            user_pct=$((user_delta * 100 / total_delta)) 
            system_pct=$((system_delta * 100 / total_delta)) 
            idle_pct=$((idle_delta * 100 / total_delta)) 
            iowait_pct=$((iowait_delta * 100 / total_delta)) 
            irq_pct=$((irq_delta * 100 / total_delta)) 
            softirq_pct=$((softirq_delta * 100 / total_delta)) 
        fi 
         
        local load=$(cat /proc/loadavg | awk '{print $1}') 
         
        print_table_row cpu_widths "$curr_time""${user_pct}%""${system_pct}%""${idle_pct}%" 
         
        prev_stat=$curr_stat 
         
        if [[ $i -lt $COUNT ]]; then 
            sleep $INTERVAL 
        fi 
    done 
     
    print_table_line "${cpu_widths[@]}" 
    echo"CPU监控完成. 采样次数: $COUNT, 间隔: ${INTERVAL}秒" 
} 
 
monitor_memory() { 
    print_banner 
    echo"【模块: 内存监控】" 
    echo"功能说明: 监控物理内存和虚拟内存使用情况、交换分区状态" 
    echo"" 
    local mem_widths=(28 11 11 11 9) 
    print_table_line "${mem_widths[@]}" 
    print_table_row mem_widths "时间""总量(MB)""可用(MB)""已用(MB)""使用率%" 
    print_table_line "${mem_widths[@]}" 
     
    for ((i=1; i<=COUNT; i++)); do 
        local curr_time=$(date +"%Y-%m-%d %H:%M:%S") 
         
        local mem_total=$(grep "^MemTotal:" /proc/meminfo | awk '{print $2}') 
        local mem_available=$(grep "^MemAvailable:" /proc/meminfo | awk '{print $2}') 
        local mem_free=$(grep "^MemFree:" /proc/meminfo | awk '{print $2}') 
        local mem_buffers=$(grep "^Buffers:" /proc/meminfo | awk '{print $2}') 
        local mem_cached=$(grep "^Cached:" /proc/meminfo | awk '{print $2}') 
        local mem_shared=$(grep "^Shmem:" /proc/meminfo | awk '{print $2}') 
        local swap_total=$(grep "^SwapTotal:" /proc/meminfo | awk '{print $2}') 
        local swap_free=$(grep "^SwapFree:" /proc/meminfo | awk '{print $2}') 
         
        # 确保值不为空 
        mem_total=${mem_total:-0} 
        mem_available=${mem_available:-0} 
        mem_free=${mem_free:-0} 
        mem_buffers=${mem_buffers:-0} 
        mem_cached=${mem_cached:-0} 
        swap_total=${swap_total:-0} 
        swap_free=${swap_free:-0} 
         
        mem_total=$((mem_total / 1024)) 
        mem_available=$((mem_available / 1024)) 
        mem_free=$((mem_free / 1024)) 
        mem_buffers=$((mem_buffers / 1024)) 
        mem_cached=$((mem_cached / 1024)) 
        local mem_used=$((mem_total - mem_available)) 
        local swap_used=$((swap_total - swap_free)) 
        if [[ $swap_total -gt 0 ]]; then 
            swap_total=$((swap_total / 1024)) 
            swap_used=$((swap_used / 1024)) 
        else 
            swap_total=0 
            swap_used=0 
        fi 
         
        local mem_pct=0 
        if [[ $mem_total -gt 0 ]]; then 
            mem_pct=$((mem_used * 100 / mem_total)) 
        else 
            mem_pct=0 
        fi 
         
        print_table_row mem_widths "$curr_time""$mem_total""$mem_available""$mem_used""${mem_pct}%" 
         
        if [[ $i -lt $COUNT ]]; then 
            sleep $INTERVAL 
        fi 
    done 
     
    print_table_line "${mem_widths[@]}" 
    echo"内存监控完成. 采样次数: $COUNT, 间隔: ${INTERVAL}秒" 
} 
 
monitor_disk() { 
    print_banner 
    echo"【模块: 磁盘I/O监控】" 
    echo"功能说明: 监控磁盘I/O吞吐量、IOPS、I/O延迟、队列深度" 
    echo"" 
    local disk_widths=(28 18 9 10 10 10 10 10) 
    print_table_line "${disk_widths[@]}" 
    print_table_row disk_widths "时间""CPU负载(1/5/15)""设备""读IOPS""读字节""写IOPS""写字节""I/O延迟" 
    print_table_line "${disk_widths[@]}" 
     
    local prev_stats=$(cat /proc/diskstats) 
     
    for ((i=1; i<=COUNT; i++)); do 
        local curr_time=$(date +"%Y-%m-%d %H:%M:%S") 
        local curr_stats=$(cat /proc/diskstats) 
         
        # 获取所有磁盘设备（排除分区） 
        local disk_devices=$(echo"$prev_stats" | awk '{if ($3 !~ /[0-9]$/) print $3}'; echo"$curr_stats" | awk '{if ($3 !~ /[0-9]$/) print $3}' | sort -u) 
         
for dev in $disk_devices; do
            local prev_line=$(echo"$prev_stats" | grep " $dev ") 
            local curr_line=$(echo"$curr_stats" | grep " $dev ") 
             
            if [[ -n "$prev_line" && -n "$curr_line" ]]; then 
                local prev_reads=$(echo$prev_line | awk '{print $6}') 
                local prev_read_sectors=$(echo$prev_line | awk '{print $7}') 
                local prev_writes=$(echo$prev_line | awk '{print $10}') 
                local prev_write_sectors=$(echo$prev_line | awk '{print $11}') 
                 
                local curr_reads=$(echo$curr_line | awk '{print $6}') 
                local curr_read_sectors=$(echo$curr_line | awk '{print $7}') 
                local curr_writes=$(echo$curr_line | awk '{print $10}') 
                local curr_write_sectors=$(echo$curr_line | awk '{print $11}') 
                 
                local read_ops=$((curr_reads - prev_reads)) 
                local write_ops=$((curr_writes - prev_writes)) 
                local read_sectors=$((curr_read_sectors - prev_read_sectors)) 
                local write_sectors=$((curr_write_sectors - prev_write_sectors)) 
                 
                local read_mb=$((read_sectors * 512 / 1024 / 1024)) 
                local write_mb=$((write_sectors * 512 / 1024 / 1024)) 
                 
                local load=$(cat /proc/loadavg) 
                local load1=$(echo$load | awk '{print $1}') 
                local load5=$(echo$load | awk '{print $2}') 
                local load15=$(echo$load | awk '{print $3}') 
                local load_str="$load1/$load5/$load15" 
                local io_delay=0 
                print_table_row disk_widths "$curr_time""$load_str""$dev""$read_ops""${read_mb}MB""$write_ops""${write_mb}MB""${io_delay}ms" 
            fi 
        done 
         
        prev_stats=$curr_stats 
         
        if [[ $i -lt $COUNT ]]; then 
            sleep $INTERVAL 
        fi 
    done 
     
    print_table_line "${disk_widths[@]}" 
    echo"磁盘I/O监控完成. 采样次数: $COUNT, 间隔: ${INTERVAL}秒" 
} 
 
monitor_network() { 
    print_banner 
    echo"【模块: 网络监控】" 
    echo"功能说明: 监控网络接口带宽使用、TCP/UDP连接统计、按进程网络使用" 
    echo"" 
    echo"━━━ 网络接口带宽监控 ━━━" 
    local net_widths=(28 10 13 13 13 13) 
    print_table_line "${net_widths[@]}" 
    print_table_row net_widths "时间""接口""接收(字节)""发送(字节)""接收(速率)""发送(速率)" 
    print_table_line "${net_widths[@]}" 
     
    local prev_netstat=$(cat /proc/net/dev) 
     
    for ((i=1; i<=COUNT; i++)); do 
        local curr_time=$(date +"%Y-%m-%d %H:%M:%S") 
        local curr_netstat=$(cat /proc/net/dev) 
         
        # 检测网络接口 
        local interface="" 
for iface in ens33 eth0 ens enp; do
if echo "$prev_netstat" | grep -q "$iface"; then
                interface=$(echo"$prev_netstat" | grep "$iface" | head -1 | awk -F: '{print $1}') 
                break 
            fi 
        done 
         
        if [[ -n "$interface" ]]; then 
            local prev_rx=$(echo"$prev_netstat" | grep "$interface:" | head -1 | awk '{print $2}') 
            local prev_tx=$(echo"$prev_netstat" | grep "$interface:" | head -1 | awk '{print $10}') 
             
            local curr_rx=$(echo"$curr_netstat" | grep "$interface:" | head -1 | awk '{print $2}') 
            local curr_tx=$(echo"$curr_netstat" | grep "$interface:" | head -1 | awk '{print $10}') 
             
            if [[ -n "$prev_rx" && -n "$curr_rx" ]]; then 
                local rx_bytes=$((curr_rx - prev_rx)) 
                local tx_bytes=$((curr_tx - prev_tx)) 
                 
                local rx_rate=$((rx_bytes / INTERVAL)) 
                local tx_rate=$((tx_bytes / INTERVAL)) 
                 
                local rx_mb=$(echo"scale=2; $rx_bytes / 1024 / 1024" | bc 2>/dev/null || echo"0") 
                local tx_mb=$(echo"scale=2; $tx_bytes / 1024 / 1024" | bc 2>/dev/null || echo"0") 
                local rx_rate_kb=$(echo"scale=2; $rx_rate / 1024" | bc 2>/dev/null || echo"0") 
                local tx_rate_kb=$(echo"scale=2; $tx_rate / 1024" | bc 2>/dev/null || echo"0") 
                 
                print_table_row net_widths "$curr_time""$interface""${rx_mb}MB""${tx_mb}MB""${rx_rate_kb}KB/s""${tx_rate_kb}KB/s" 
            fi 
        else 
            print_table_row net_widths "$curr_time""-""-""-""-""-" 
        fi 
         
        prev_netstat=$curr_netstat 
         
        if [[ $i -lt $COUNT ]]; then 
            sleep $INTERVAL 
        fi 
    done 
     
    print_table_line "${net_widths[@]}" 
    echo"网络监控完成. 采样次数: $COUNT, 间隔: ${INTERVAL}秒" 
} 
 
monitor_process() { 
    print_banner 
    echo"【模块: 进程监控】" 
    echo"功能说明: 按进程监控CPU、内存、I/O使用情况，按资源使用排序" 
    echo"" 
    echo"━━━ CPU占用Top 10进程 ━━━" 
    local proc_cpu_widths=(11 11 7 7 10 16 23) 
    print_table_line "${proc_cpu_widths[@]}" 
    print_table_row proc_cpu_widths "PID""用户""CPU%""内存%""VSZ(KB)""运行时间""命令" 
    print_table_line "${proc_cpu_widths[@]}" 
     
    ps aux --no-headers 2>/dev/null | sort -rn -k 3 | head -10 | whileread line; do 
        local pid=$(echo$line | awk '{print $2}') 
        local user=$(echo$line | awk '{print $1}') 
        local cpu=$(echo$line | awk '{print $3}') 
        local mem=$(echo$line | awk '{print $4}') 
        local vsz=$(echo$line | awk '{print $5}') 
        local time=$(echo$line | awk '{print $10}') 
        local comm=$(echo$line | awk '{print $11}') 
         
        print_table_row proc_cpu_widths "$pid""$user""${cpu}%""${mem}%""$vsz""$time""$comm" 
    done 
     
    print_table_line "${proc_cpu_widths[@]}" 
    echo"" 
    echo"━━━ 内存占用Top 10进程 ━━━" 
    local proc_mem_widths=(11 11 7 10 10 16 23) 
    print_table_line "${proc_mem_widths[@]}" 
    print_table_row proc_mem_widths "PID""用户""内存%""RSS(KB)""VSZ(KB)""运行时间""命令" 
    print_table_line "${proc_mem_widths[@]}" 
     
    ps aux --no-headers 2>/dev/null | sort -rn -k 4 | head -10 | whileread line; do 
        local pid=$(echo$line | awk '{print $2}') 
        local user=$(echo$line | awk '{print $1}') 
        local mem=$(echo$line | awk '{print $4}') 
        local rss=$(echo$line | awk '{print $6}') 
        local vsz=$(echo$line | awk '{print $5}') 
        local time=$(echo$line | awk '{print $10}') 
        local comm=$(echo$line | awk '{print $11}') 
         
        print_table_row proc_mem_widths "$pid""$user""${mem}%""$rss""$vsz""$time""$comm" 
    done 
     
    print_table_line "${proc_mem_widths[@]}" 
    echo"" 
    echo"━━━ 线程数Top 10进程 ━━━" 
    local proc_thread_widths=(11 11 23) 
    print_table_line "${proc_thread_widths[@]}" 
    print_table_row proc_thread_widths "PID""线程数""命令" 
    print_table_line "${proc_thread_widths[@]}" 
     
    ps -eLf --no-headers 2>/dev/null | awk '{print $2, $NF}' | sort | uniq -c | sort -rn | head -10 | whileread count pid comm; do 
        print_table_row proc_thread_widths "$pid""$count""$comm" 
    done 
     
    print_table_line "${proc_thread_widths[@]}" 
    echo"进程监控完成. 采样次数: $COUNT, 间隔: ${INTERVAL}秒" 
} 
 
monitor_slab() { 
    print_banner 
    echo"【模块: 内核缓存监控】" 
    echo"功能说明: 监控内核SLAB缓存使用情况，包括dentry、inode等" 
    echo"" 
     
    if [[ ! -f /proc/slabinfo ]]; then 
        echo"错误: 系统不支持 /proc/slabinfo (可能需要root权限)" 
        echo"尝试: sudo $0 slab" 
        return 1 
    fi 
     
    local slab_widths=(20 11 11 11 11 12) 
    print_table_line "${slab_widths[@]}" 
    print_table_row slab_widths "缓存名称""对象数""对象大小""已使用""缓存大小""利用率" 
    print_table_line "${slab_widths[@]}" 
     
    grep -E "^(dentry|inode_|kmalloc-|vm_area_struct)" /proc/slabinfo 2>/dev/null | whileread line; do 
        local name=$(echo$line | awk '{print $1}') 
        local objs=$(echo$line | awk '{print $2}') 
        local obj_size=$(echo$line | awk '{print $3}') 
        local used=$(echo$line | awk '{print $4}') 
        local cache_size=$(echo$line | awk '{print $5}') 
         
        local usage_pct=0 
        if [[ $objs -gt 0 ]]; then 
            usage_pct=$((used * 100 / objs)) 
        fi 
         
        print_table_row slab_widths "$name""$objs""$obj_size""$used""$cache_size""${usage_pct}%" 
    done 
     
    print_table_line "${slab_widths[@]}" 
    echo"" 
    echo"缓存说明:" 
    echo"dentry: 目录项缓存" 
    echo"inode_: inode缓存" 
    echo"kmalloc-: 内核内存分配" 
    echo"vm_area_struct: 虚拟内存区域" 
    print_table_line "${slab_widths[@]}" 
    echo"内核缓存监控完成. 采样次数: $COUNT, 间隔: ${INTERVAL}秒" 
} 
 
monitor_overview() { 
    print_banner 
    echo"【模块: 系统概览】" 
    echo"功能说明: 综合监控CPU、内存、磁盘、网络等系统资源" 
    echo"" 
    echo"━━━ CPU使用率 ━━━" 
    local ov_cpu_widths=(28 7 7 7) 
    print_table_line "${ov_cpu_widths[@]}" 
    print_table_row ov_cpu_widths "时间""用户%""系统%""空闲%" 
    print_table_line "${ov_cpu_widths[@]}" 
     
    local prev_stat=$(cat /proc/stat | grep "^cpu ") 
    local cpu_stats=() 
     
    for ((i=1; i<=COUNT; i++)); do 
        local curr_time=$(date +"%Y-%m-%d %H:%M:%S") 
        local curr_stat=$(cat /proc/stat | grep "^cpu ") 
         
        local prev_user=$(echo$prev_stat | awk '{print $2}') 
        local prev_nice=$(echo$prev_stat | awk '{print $3}') 
        local prev_system=$(echo$prev_stat | awk '{print $4}') 
        local prev_idle=$(echo$prev_stat | awk '{print $5}') 
         
        local curr_user=$(echo$curr_stat | awk '{print $2}') 
        local curr_nice=$(echo$curr_stat | awk '{print $3}') 
        local curr_system=$(echo$curr_stat | awk '{print $4}') 
        local curr_idle=$(echo$curr_stat | awk '{print $5}') 
         
        local user_delta=$((curr_user - prev_user)) 
        local nice_delta=$((curr_nice - prev_nice)) 
        local system_delta=$((curr_system - prev_system)) 
        local idle_delta=$((curr_idle - prev_idle)) 
         
        local total_delta=$((user_delta + nice_delta + system_delta + idle_delta)) 
         
        local user_pct=0 
        local system_pct=0 
        local idle_pct=100 
         
        if [[ $total_delta -gt 0 ]]; then 
            user_pct=$((user_delta * 100 / total_delta)) 
            system_pct=$((system_delta * 100 / total_delta)) 
            idle_pct=$((idle_delta * 100 / total_delta)) 
        fi 
         
        print_table_row ov_cpu_widths "$curr_time""${user_pct}%""${system_pct}%""${idle_pct}%" 
         
        prev_stat=$curr_stat 
         
        if [[ $i -lt $COUNT ]]; then 
            sleep $INTERVAL 
        fi 
    done 
     
    print_table_line "${ov_cpu_widths[@]}" 
    echo"" 
    echo"━━━ 内存使用情况 ━━━" 
    local ov_mem_widths=(28 11 11 11 9) 
    print_table_line "${ov_mem_widths[@]}" 
    print_table_row ov_mem_widths "时间""总量(MB)""可用(MB)""已用(MB)""使用率%" 
    print_table_line "${ov_mem_widths[@]}" 
     
    for ((i=1; i<=COUNT; i++)); do 
        local curr_time=$(date +"%Y-%m-%d %H:%M:%S") 
         
        local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}' || echo 0) 
        local mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}' || echo 0) 
         
        mem_total=${mem_total:-0} 
        mem_available=${mem_available:-0} 
         
        mem_total=$((mem_total / 1024)) 
        mem_available=$((mem_available / 1024)) 
        local mem_used=$((mem_total - mem_available)) 
        local mem_pct=0 
        if [[ $mem_total -gt 0 ]]; then 
            mem_pct=$((mem_used * 100 / mem_total)) 
        else 
            mem_pct=0 
        fi 
         
        print_table_row ov_mem_widths "$curr_time""$mem_total""$mem_available""$mem_used""${mem_pct}%" 
         
        if [[ $i -lt $COUNT ]]; then 
            sleep $INTERVAL 
        fi 
    done 
     
    print_table_line "${ov_mem_widths[@]}" 
    echo"" 
    echo"━━━ 系统负载 ━━━" 
    local ov_load_widths=(28 7 7 7) 
    print_table_line "${ov_load_widths[@]}" 
    print_table_row ov_load_widths "时间""1分钟""5分钟""15分钟" 
    print_table_line "${ov_load_widths[@]}" 
     
    for ((i=1; i<=COUNT; i++)); do 
        local curr_time=$(date +"%Y-%m-%d %H:%M:%S") 
        local load=$(cat /proc/loadavg) 
        local load1=$(echo$load | awk '{print $1}') 
        local load5=$(echo$load | awk '{print $2}') 
        local load15=$(echo$load | awk '{print $3}') 
         
        print_table_row ov_load_widths "$curr_time""$load1""$load5""$load15" 
         
        if [[ $i -lt $COUNT ]]; then 
            sleep $INTERVAL 
        fi 
    done 
     
    print_table_line "${ov_load_widths[@]}" 
    echo"系统概览完成. 采样次数: $COUNT, 间隔: ${INTERVAL}秒" 
} 
 
monitor_once() { 
    print_banner 
    echo"【模式: 单次全检测】" 
    print_separator 
     
    echo"━━━ 系统信息 ━━━" 
    echo"主机名: $(hostname)" 
    echo"操作系统: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"'"'" -f2 || echo 'Unknown')" 
    echo"内核版本: $(uname -r)" 
    echo"架构: $(uname -m)" 
    echo"CPU型号: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | sed 's/^[ \t]*//')" 
    echo"CPU核心数: $(nproc)" 
    echo"总内存: $(grep MemTotal /proc/meminfo | awk '{print $2/1024/1024 " GB"}')" 
    echo"" 
     
    echo"━━━ CPU使用率 ━━━" 
    local once_cpu_widths=(28 7 7 7) 
    print_table_line "${once_cpu_widths[@]}" 
    print_table_row once_cpu_widths "时间""用户%""系统%""空闲%" 
    print_table_line "${once_cpu_widths[@]}" 
     
    local prev_stat=$(cat /proc/stat | grep "^cpu ") 
    sleep 1 
    local curr_stat=$(cat /proc/stat | grep "^cpu ") 
     
    local prev_user=$(echo$prev_stat | awk '{print $2}') 
    local prev_system=$(echo$prev_stat | awk '{print $4}') 
    local prev_idle=$(echo$prev_stat | awk '{print $5}') 
     
    local curr_user=$(echo$curr_stat | awk '{print $2}') 
    local curr_system=$(echo$curr_stat | awk '{print $4}') 
    local curr_idle=$(echo$curr_stat | awk '{print $5}') 
     
    local user_delta=$((curr_user - prev_user)) 
    local system_delta=$((curr_system - prev_system)) 
    local idle_delta=$((curr_idle - prev_idle)) 
    local total_delta=$((user_delta + system_delta + idle_delta)) 
     
    local user_pct=0 
    local system_pct=0 
    local idle_pct=100 
     
    if [[ $total_delta -gt 0 ]]; then 
        user_pct=$((user_delta * 100 / total_delta)) 
        system_pct=$((system_delta * 100 / total_delta)) 
        idle_pct=$((idle_delta * 100 / total_delta)) 
    fi 
     
    local curr_time=$(date +"%Y-%m-%d %H:%M:%S") 
    print_table_row once_cpu_widths "$curr_time""${user_pct}%""${system_pct}%""${idle_pct}%" 
    print_table_line "${once_cpu_widths[@]}" 
    echo"" 
     
    echo"━━━ 内存使用情况 ━━━" 
    local once_mem_widths=(28 11 11 11 9) 
    print_table_line "${once_mem_widths[@]}" 
    print_table_row once_mem_widths "时间""总量(MB)""可用(MB)""已用(MB)""使用率%" 
    print_table_line "${once_mem_widths[@]}" 
     
    local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}' || echo 0) 
    local mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}' || echo 0) 
     
    mem_total=${mem_total:-0} 
    mem_available=${mem_available:-0} 
     
    mem_total=$((mem_total / 1024)) 
    mem_available=$((mem_available / 1024)) 
    local mem_used=$((mem_total - mem_available)) 
    local mem_pct=0 
    if [[ $mem_total -gt 0 ]]; then 
        mem_pct=$((mem_used * 100 / mem_total)) 
    else 
        mem_pct=0 
    fi 
     
    print_table_row once_mem_widths "$curr_time""$mem_total""$mem_available""$mem_used""${mem_pct}%" 
    print_table_line "${once_mem_widths[@]}" 
    echo"" 
     
    echo"━━━ 磁盘使用情况 ━━━" 
    local once_disk_widths=(26 8 8 8 9 16) 
    print_table_line "${once_disk_widths[@]}" 
    print_table_row once_disk_widths "文件系统""大小""已用""可用""使用率%""挂载点" 
    print_table_line "${once_disk_widths[@]}" 
     
    df -h 2>/dev/null | grep -vE "^(Filesystem|文件系统)" | head -10 | whileread filesystem size used avail pct mount; do 
        print_table_row once_disk_widths "$filesystem""$size""$used""$avail""$pct""$mount" 
    done 
     
    print_table_line "${once_disk_widths[@]}" 
    echo"" 
     
    echo"━━━ 网络连接统计 ━━━" 
    local once_net_widths=(8 9 9 9 9 9) 
    print_table_line "${once_net_widths[@]}" 
    print_table_row once_net_widths "协议""连接数""监听""已建立""等待关闭""其他" 
    print_table_line "${once_net_widths[@]}" 
     
    local tcp_total=$(ss -tan 2>/dev/null | tail -n +2 | wc -l) 
    tcp_total=${tcp_total:-0} 
    local tcp_listen=$(ss -tan 2>/dev/null | grep LISTEN | wc -l) 
    tcp_listen=${tcp_listen:-0} 
    local tcp_established=$(ss -tan 2>/dev/null | grep ESTAB | wc -l) 
    tcp_established=${tcp_established:-0} 
    local tcp_timewait=$(ss -tan 2>/dev/null | grep TIME-WAIT | wc -l) 
    tcp_timewait=${tcp_timewait:-0} 
    local tcp_other=$((tcp_total - tcp_listen - tcp_established - tcp_timewait)) 
    if [[ $tcp_other -lt 0 ]]; then 
        tcp_other=0 
    fi 
     
    print_table_row once_net_widths "TCP""$tcp_total""$tcp_listen""$tcp_established""$tcp_timewait""$tcp_other" 
     
    local udp_total=$(ss -uan 2>/dev/null | tail -n +2 | wc -l) 
    udp_total=${udp_total:-0} 
    print_table_row once_net_widths "UDP""$udp_total""-""-""-""-" 
     
    print_table_line "${once_net_widths[@]}" 
    echo"" 
     
    echo"━━━ Top 5 CPU进程 ━━━" 
    local once_proccpu_widths=(11 11 7 7 25) 
    print_table_line "${once_proccpu_widths[@]}" 
    print_table_row once_proccpu_widths "PID""用户""CPU%""内存%""命令" 
    print_table_line "${once_proccpu_widths[@]}" 
     
    ps aux --no-headers 2>/dev/null | sort -rn -k 3 | head -5 | whileread line; do 
        local pid=$(echo$line | awk '{print $2}') 
        local user=$(echo$line | awk '{print $1}') 
        local cpu=$(echo$line | awk '{print $3}') 
        local mem=$(echo$line | awk '{print $4}') 
        local comm=$(echo$line | awk '{print $11}') 
         
        print_table_row once_proccpu_widths "$pid""$user""${cpu}%""${mem}%""$comm" 
    done 
     
    print_table_line "${once_proccpu_widths[@]}" 
    echo"" 
     
    echo"━━━ Top 5 内存进程 ━━━" 
    local once_procmem_widths=(11 11 7 10 25) 
    print_table_line "${once_procmem_widths[@]}" 
    print_table_row once_procmem_widths "PID""用户""内存%""RSS(KB)""命令" 
    print_table_line "${once_procmem_widths[@]}" 
     
    ps aux --no-headers 2>/dev/null | sort -rn -k 4 | head -5 | whileread line; do 
        local pid=$(echo$line | awk '{print $2}') 
        local user=$(echo$line | awk '{print $1}') 
        local mem=$(echo$line | awk '{print $4}') 
        local rss=$(echo$line | awk '{print $6}') 
        local comm=$(echo$line | awk '{print $11}') 
         
        print_table_row once_procmem_widths "$pid""$user""${mem}%""$rss""$comm" 
    done 
     
    print_table_line "${once_procmem_widths[@]}" 
    echo"" 
     
    echo"单次全检测完成!" 
} 
 
main() {
parse_args "$@"
validate_args
for cmd in awk grep head tail ps ss df bc date cat printf; do check_command_exists "$cmd"; done
if [[ -n "$REPORT_FILE" ]]; then
exec > >(tee "$REPORT_FILE")
fi
case "$MODULE" in
        cpu) 
            monitor_cpu 
            ;; 
        memory) 
            monitor_memory 
            ;; 
        disk) 
            monitor_disk 
            ;; 
        network) 
            monitor_network 
            ;; 
        process) 
            monitor_process 
            ;; 
        slab) 
            monitor_slab 
            ;; 
        overview) 
            monitor_overview 
            ;; 
        once) 
            monitor_once 
            ;; 
        *) 
            print_banner 
            echo"错误: 未知模块 '$MODULE'" 
            echo"" 
            print_usage 
            exit 1 
            ;; 
    esac 
} 
 
main "$@"
