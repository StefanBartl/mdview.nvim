// ADD: Annotations
// src/client/transport/trabsport.interface.ts
//
export interface Transport {
  /**
   * Open / initialize the transport (connect or wait for ready).
   * May perform async handshake.
   */
  initialize(): Promise<void>;

  /**
   * Send a textual message (JSON encoded).
   */
  sendMessage(message: string): Promise<void>;

  /**
   * Register callback for inbound textual messages.
   */
  onMessage(cb: (message: string) => void): void;

  /**
   * Optional: send a best-effort datagram (unreliable).
   */
  sendDatagram?(data: Uint8Array): void;

  /**
   * Close the transport.
   */
  close(): Promise<void>;
}
