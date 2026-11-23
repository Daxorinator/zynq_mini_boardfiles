// Properties on the internal state of ple_mac (included before the final endmodule of a generated copy, see run_ple_mac.sh)
  // TX: the state register stays in its encoding; TXEN is low whenever the state machine is idle
  always @(posedge clk125) begin
    assert(tx_st <= T_GAP);
    if (tx_st == T_IDLE) assert(!txen);
    if (tx_st == T_PRE) assert(tx_ph <= 6);
    if (tx_st == T_GAP) assert(tx_ph <= 15);
    if (tx_st == T_DATA) assert(txen);                   // data bytes are only ever sent with TXEN high
    if (tx_busy == 0) assert(tx_st == T_IDLE || tx_st == T_GAP && tx_ph == 0 && 0 || tx_st == T_IDLE);
  end
  // RX: the byte index never passes the 320-byte buffer, a frame in progress and a ready frame never coexist, the stored length fits the buffer
  always @(posedge rx_clk) begin
    assert(rx_idx <= 320);
    assert(!(rx_active && rx_ready));
    assert(rx_len <= 320);
    if (rx_active) assert(rx_idx >= 1);
  end
  // reachability: a transmitted frame can complete and a received frame can become ready (these catch state machines that hang)
  always @(posedge clk125) cover(frames_tx == 1);
  always @(posedge rx_clk) cover(rx_ready);
