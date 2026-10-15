// Why this patches listen() instead of passing a flag: @scalar/cli's `document serve` has no
// option for the address it binds to, and hands @hono/node-server no hostname, so Node's
// default (every interface) wins. A proxy in front would not help either, since the CLI
// behind it would still be listening on every interface.
//
// Why only IP addresses: "localhost" resolves to different addresses on different machines
// (::1 first on some, 127.0.0.1 on others), so the check below could not tell a correct
// bind from a wrong one.
import net from "node:net";

const bindHost = process.env.SCALAR_PREVIEW_BIND_HOST;

if (bindHost === undefined || net.isIP(bindHost) === 0) {
  console.error(`scalar-preview: SCALAR_PREVIEW_BIND_HOST must be an IP address, got ${JSON.stringify(bindHost)}`);
  process.exit(1);
}

const isPort = (value) => typeof value === "number" || (typeof value === "string" && /^\d+$/.test(value));

// IPv6 addresses can be written several ways; URL gives one canonical form for both sides.
const normalize = (address) => (net.isIPv6(address) ? new URL(`http://[${address}]`).hostname : address);

// A host slot that names no particular host makes node listen on every interface, so all of
// these count as "not specified". Listing the spellings ("::", "::0", ...) would miss the next
// one, so IPv6 is compared in canonical form instead.
const namesNoHost = (host) => {
  if (host === undefined || host === null || host === "") {
    return true;
  }
  if (typeof host !== "string") {
    return false;
  }
  return host === "0.0.0.0" || (net.isIPv6(host) && normalize(host) === "[::]");
};

const originalListen = net.Server.prototype.listen;

net.Server.prototype.listen = function (...args) {
  const [first, second] = args;

  if (isPort(first)) {
    // listen(port), listen(port, cb) and listen(port, backlog) have no host slot to fill; in
    // every other form the second argument is the host, so it is replaced in place and a
    // backlog or callback after it stays where node expects it.
    if (args.length === 1 || typeof second === "function" || typeof second === "number") {
      args.splice(1, 0, bindHost);
    } else if (namesNoHost(second)) {
      args[1] = bindHost;
    }
  } else if (first !== null && typeof first === "object" && first.port !== undefined) {
    if (namesNoHost(first.host)) {
      args[0] = { ...first, host: bindHost };
    }
  }

  // Checked after binding rather than trusted from the rewrite above: if @scalar/cli ever
  // listens in a way the rewrite does not recognize, stopping is safer than quietly staying
  // reachable from the network. Prepended so a listener the server registered before calling
  // listen() cannot announce itself first.
  //
  // The line printed on success is what the plugin waits for before opening the browser. It
  // cannot rely on this script having loaded at all: npm can replace NODE_OPTIONS (see
  // `npm_config_node_options` in init.lua) and then there is no check and nothing to
  // exit, so the absence of this line is the only sign left that the bind is not in effect.
  this.prependOnceListener("listening", () => {
    const address = this.address();
    if (address === null || typeof address !== "object") {
      return;
    }
    if (normalize(address.address) !== normalize(bindHost)) {
      console.error(`scalar-preview: refusing to serve on ${address.address}, expected ${bindHost}`);
      process.exit(1);
    }
    // Bracketed like a URL authority so that "::1" and its port do not run together.
    const shown = net.isIPv6(address.address) ? `[${address.address}]` : address.address;
    console.log(`scalar-preview: bound ${shown}:${address.port}`);
  });

  return originalListen.apply(this, args);
};
