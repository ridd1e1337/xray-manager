# Convert one share link into an Xray outbound (outbound subscriptions).
# Input: a raw link string. $tag: outbound tag.
# Output: {tag, outbound, name} or {error}. Unknown fields are ignored;
# a link that cannot be expressed safely (e.g. allowInsecure) is rejected.
def urid:
  # Percent-decoding over UTF-8 bytes.
  [explode | . as $c | foreach range(0; length) as $i ({skip:0, out:null};
     if .skip > 0 then {skip:(.skip - 1), out:null}
     elif $c[$i] == 37 and ($i + 2) < ($c|length) then
       {skip:2, out:([$c[$i+1], $c[$i+2]] | implode | ascii_downcase
         | (explode | map(if . >= 97 then . - 87 else . - 48 end) | .[0] * 16 + .[1]))}
     elif $c[$i] == 43 then {skip:0, out:32}
     else {skip:0, out:$c[$i]} end; .out) | select(. != null)]
  | . as $bytes
  # UTF-8 bytes → code points.
  | [foreach range(0; length) as $i ({need:0, cp:0, out:null};
      $bytes[$i] as $b |
      if .need > 0 then {need:(.need - 1), cp:(.cp * 64 + ($b % 64))} | (if .need == 0 then .out = .cp else .out = null end)
      elif $b < 128 then {need:0, cp:0, out:$b}
      elif $b >= 240 then {need:3, cp:($b % 8), out:null}
      elif $b >= 224 then {need:2, cp:($b % 16), out:null}
      else {need:1, cp:($b % 32), out:null} end; .out) | select(. != null)] | implode;
def qs: if . == null or . == "" then {} else split("&") | map(select(length > 0) | split("=") | {key:(.[0]|urid), value:((.[1:] | join("=")) | urid)}) | from_entries end;
def b64d: gsub("-"; "+") | gsub("_"; "/") | (. + ("=" * ((4 - (length % 4)) % 4))) | @base64d;
def hostport: if test("^\\[") then capture("^\\[(?<h>[^\\]]+)\\]:(?<p>[0-9]+)") else capture("^(?<h>[^:]+):(?<p>[0-9]+)") end | {address:.h, port:(.p|tonumber)};
def fail($m): {error:$m};
def stream($q):
  ($q.type // $q.net // "tcp") as $net |
  ({tcp:"raw", raw:"raw", ws:"ws", grpc:"grpc", httpupgrade:"httpupgrade", xhttp:"xhttp", splithttp:"xhttp", kcp:"kcp", mkcp:"kcp"}[$net]) as $n |
  if $n == null then error("不支持的传输：" + $net) else . end |
  ($q.security // "none") as $sec |
  if ($q.allowInsecure // $q.insecure // "0") | IN("1", "true") then error("链接要求跳过证书验证，已拒绝") else . end |
  {network:$n}
  + (if $n == "ws" then {wsSettings:({path:($q.path // "/")} + (if $q.host then {host:$q.host} else {} end))}
     elif $n == "grpc" then {grpcSettings:{serviceName:($q.serviceName // $q.path // ""), multiMode:(($q.mode // "") == "multi")}}
     elif $n == "httpupgrade" then {httpupgradeSettings:({path:($q.path // "/")} + (if $q.host then {host:$q.host} else {} end))}
     elif $n == "xhttp" then {xhttpSettings:({path:($q.path // "/"), mode:($q.mode // "auto")} + (if $q.host then {host:$q.host} else {} end))}
     elif $n == "raw" and ($q.headerType // "none") == "http" then {rawSettings:{header:{type:"http", request:{path:[($q.path // "/")], headers:{Host:[($q.host // "")]}}}}}
     else {} end)
  + (if $sec == "tls" then {security:"tls", tlsSettings:({serverName:($q.sni // $q.host // ""), fingerprint:($q.fp // "chrome")}
        + (if $q.alpn then {alpn:($q.alpn | split(","))} else {} end)
        + (if $q.pcs then {pinnedPeerCertSha256:$q.pcs} else {} end))}
     elif $sec == "reality" then {security:"reality", realitySettings:{serverName:($q.sni // ""), fingerprint:($q.fp // "chrome"),
        password:($q.pbk // ""), shortId:($q.sid // ""), spiderX:($q.spx // "/")}}
     else {} end)
  # fm: the finalmask object (JSON), as written by this manager's VLESS links.
  + (if ($q.fm // "") == "" then {} else
       ($q.fm | try fromjson catch null) as $fm |
       if ($fm | type) == "object" and ($fm | keys - ["tcp", "udp", "quicParams"] | length) == 0
          and (($fm.tcp // []) | type) == "array" and (($fm.udp // []) | type) == "array" and (($fm.quicParams // {}) | type) == "object"
       then {finalmask:$fm} else error("链接里的 fm（finalmask）无效") end
     end);
. as $link |
(try (
  ($link | capture("^(?<scheme>[a-z0-9]+)://(?<rest>.*)$")) as $m |
  ($m.rest | split("#")) as $parts | ($parts[0]) as $body | (($parts[1:] | join("#")) | urid) as $name |
  ($body | split("?")) as $bq | ($bq[0]) as $auth | ($bq[1:] | join("?") | qs) as $q |
  if $m.scheme == "vmess" then
    ($body | b64d | fromjson) as $v |
    {name:($v.ps // ""), outbound:{protocol:"vmess",
      settings:{vnext:[{address:$v.add, port:($v.port|tonumber), users:[{id:$v.id, security:($v.scy // "auto"), alterId:(($v.aid // 0)|tonumber)}]}]},
      streamSettings:stream({type:($v.net // "tcp"), security:(if ($v.tls // "") == "tls" then "tls" else "none" end), sni:($v.sni // null),
        host:($v.host // null), path:($v.path // null), fp:($v.fp // null), alpn:($v.alpn // null), headerType:($v.type // null), serviceName:($v.path // null)} | with_entries(select(.value != null and .value != "")))}}
  elif ($m.scheme | IN("vless", "trojan")) then
    ($auth | split("@")) as $ua | ($ua[0] | urid) as $cred | ($ua[1:] | join("@") | hostport) as $hp |
    {name:$name, outbound:(
      if $m.scheme == "vless" then
        {protocol:"vless", settings:{vnext:[{address:$hp.address, port:$hp.port,
          users:[{id:$cred, encryption:($q.encryption // "none")} + (if ($q.flow // "") != "" then {flow:$q.flow} else {} end)]}]}}
      else {protocol:"trojan", settings:{servers:[{address:$hp.address, port:$hp.port, password:$cred}]}} end
      + {streamSettings:stream(if $m.scheme == "trojan" and ($q.security // "") == "" then $q + {security:"tls"} else $q end)})}
  elif $m.scheme == "ss" then
    ($auth | split("@")) as $ua |
    (if ($ua|length) > 1 then {u:($ua[0] | urid), hp:($ua[1:] | join("@"))} else ($ua[0] | b64d | split("@") | {u:.[0], hp:(.[1:] | join("@"))}) end) as $x |
    ($x.u | if test(":") then . else b64d end | split(":")) as $mp |
    ($x.hp | hostport) as $hp |
    if ($q.plugin // "") != "" then error("不支持 SS 插件") else . end |
    {name:$name, outbound:{protocol:"shadowsocks", settings:{servers:[{address:$hp.address, port:$hp.port, method:$mp[0], password:($mp[1:] | join(":"))}]}}}
  elif ($m.scheme | IN("hysteria2", "hy2")) then
    ($auth | split("@")) as $ua | ($ua[0] | urid) as $cred | ($ua[1:] | join("@") | sub("/$"; "") | hostport) as $hp |
    if ($q.insecure // "0") | IN("1", "true") then error("链接要求跳过证书验证，已拒绝") else . end |
    {name:$name, outbound:{protocol:"hysteria", settings:{version:2, address:$hp.address, port:$hp.port},
      streamSettings:({network:"hysteria", hysteriaSettings:{version:2, auth:$cred}, security:"tls",
        tlsSettings:({serverName:($q.sni // $hp.address), alpn:["h3"]} + (if $q.pinSHA256 then {pinnedPeerCertSha256:$q.pinSHA256} else {} end))}
        + (if ($q.obfs // "") == "salamander" then {finalmask:{udp:[{type:"salamander", settings:{password:($q["obfs-password"] // "")}}]}} else {} end))}}
  elif ($m.scheme | IN("socks", "socks5", "http", "https")) then
    ($auth | split("@")) as $ua |
    (if ($ua|length) > 1 then ($ua[0] | urid | if test(":") then . else b64d end | split(":")) else [] end) as $up |
    ($ua[-1] | sub("/$"; "") | hostport) as $hp |
    {name:$name, outbound:({protocol:(if ($m.scheme | IN("http", "https")) then "http" else "socks" end),
      settings:({address:$hp.address, port:$hp.port} + (if ($up|length) > 1 then {user:$up[0], pass:($up[1:] | join(":"))} else {} end))}
      + (if $m.scheme == "https" then {streamSettings:{security:"tls", tlsSettings:{serverName:$hp.address}}} else {} end))}
  else error("不支持的协议：" + $m.scheme) end
  | .outbound.tag = $tag | {tag:$tag, name, outbound}
) catch fail(if type == "string" then . else "无法解析的链接" end))
