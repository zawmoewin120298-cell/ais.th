#!/usr/bin/env python3
import argparse
import asyncio
import ssl


async def pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    try:
        while not reader.at_eof():
            data = await reader.read(65536)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except Exception:
        pass
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


async def handle_client(
    local_reader: asyncio.StreamReader,
    local_writer: asyncio.StreamWriter,
    remote_host: str,
    remote_port: int,
    sni: str,
    ssl_ctx: ssl.SSLContext | None,
    use_ssl: bool,
):
    try:
        first_chunk = await asyncio.wait_for(local_reader.read(4096), timeout=10)
        if not first_chunk:
            local_writer.close()
            return

        # HTTP CONNECT ဖြစ်နေရင် 200 Connection Established ပြန်ပေးပြီး tunnel ဖွင့်မယ်
        if first_chunk.upper().startswith(b"CONNECT "):
            local_writer.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            await local_writer.drain()
            initial_payload = b""
        else:
            initial_payload = first_chunk

        if use_ssl:
            remote_reader, remote_writer = await asyncio.open_connection(
                host=remote_host,
                port=remote_port,
                ssl=ssl_ctx,
                server_hostname=sni,
            )
        else:
            remote_reader, remote_writer = await asyncio.open_connection(
                host=remote_host,
                port=remote_port,
            )

        if initial_payload:
            remote_writer.write(initial_payload)
            await remote_writer.drain()

        await asyncio.gather(
            pipe(local_reader, remote_writer),
            pipe(remote_reader, local_writer),
        )
    except Exception as e:
        print(f"[py-sni-relay] error: {e}", flush=True)
        try:
            local_writer.close()
            await local_writer.wait_closed()
        except Exception:
            pass


async def main():
    parser = argparse.ArgumentParser(description="Python SNI + TCP/SSL Tunnel Relay")
    parser.add_argument("--listen-host", default="127.0.0.1")
    parser.add_argument("--listen-port", type=int, default=19001)
    parser.add_argument("--remote-host", required=True)
    parser.add_argument("--remote-port", type=int, default=443)
    parser.add_argument("--sni", default=None)
    parser.add_argument("--no-ssl", action="store_true", help="Plain TCP mode (disable TLS)")
    parser.add_argument("--insecure", action="store_true", help="Skip TLS cert verification")
    args = parser.parse_args()

    use_ssl = not args.no_ssl
    sni = args.sni or args.remote_host

    ssl_ctx = None
    if use_ssl:
        ssl_ctx = ssl.create_default_context()
        if args.insecure:
            ssl_ctx.check_hostname = False
            ssl_ctx.verify_mode = ssl.CERT_NONE

    server = await asyncio.start_server(
        lambda r, w: handle_client(
            r, w, args.remote_host, args.remote_port, sni, ssl_ctx, use_ssl
        ),
        host=args.listen_host,
        port=args.listen_port,
    )

    addrs = ", ".join(str(s.getsockname()) for s in (server.sockets or []))
    mode_str = f"TLS(SNI={sni}, insecure={args.insecure})" if use_ssl else "TCP"
    print(
        f"[py-sni-relay] Listening on {addrs} -> {args.remote_host}:{args.remote_port} [{mode_str}]",
        flush=True,
    )

    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())

