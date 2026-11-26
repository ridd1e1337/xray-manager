# Convert one effective Xray VLESS outbound. Unknown nonempty options are
# rejected for narrower formats; the full native Xray object remains available.
def unsupported($message): error({sb_reason:$message});
def meaningful: . != null and . != "" and . != [] and . != {};
def compact: with_entries(select(.value != null));
def only($allowed; $where):
  . as $original |
  [to_entries[] | select((.key as $key | $allowed | index($key)) == null and (.value|meaningful)) | .key] as $unknown |
  if ($unknown|length)>0 then unsupported($where + " 无法完整表达字段：" + ($unknown|join(",")) + "；请使用原生 Xray JSON") else $original end;
def mapped($mapping; $where):
  only(($mapping|keys); $where) | to_entries | map(select(.value!=null) | .key=$mapping[.key]) | from_entries;
def host_header: [.headers // {} | to_entries[] | select(.key|ascii_downcase=="host") | .value] | first // "";
def request_host: if (.host // "")!="" then .host else host_header end;
def ws_headers:
  . as $w | (.headers // {}) as $headers |
  if ($w.host // "")=="" then $headers else ($headers|with_entries(select(.key|ascii_downcase!="host"))) + {Host:$w.host} end;
def ws_path:
  (.path // "/") as $path |
  ($path | split("?")) as $parts |
  if ($parts|length)==1 then {path:$path,early:0} else
    ($parts[1:]|join("?")|split("&")) as $query |
    ([$query[] | select(startswith("ed=")) | ltrimstr("ed=")] | first // "0") as $ed |
    if ($ed|test("^[0-9]+$")|not) then unsupported("WebSocket ed 必须是数字") else
      ($query|map(select(startswith("ed=")|not))|join("&")) as $rest |
      {path:($parts[0]+(if $rest=="" then "" else "?"+$rest end)),early:($ed|tonumber)} end end;
def root_options:
  only(["protocol","tag","settings","streamSettings","mux"]; $mode) |
  if (.protocol|IN("vless","vmess","trojan","shadowsocks")|not) then unsupported("导出器只接受 VLESS/VMess/Trojan/Shadowsocks") else . end |
  if (.mux // {})!={} and .mux!={enabled:false} then unsupported($mode+" 无法完整表达 Xray Mux；请使用原生 Xray JSON") else . end |
  if .settings.reverse!=null then unsupported($mode+" 不支持 VLESS reverse；请使用原生 Xray JSON") else . end |
  if (.protocol|IN("vless","vmess")) then
    .settings |= only(["vnext"]; $mode+" settings") |
    if (.settings.vnext|length)!=1 or (.settings.vnext[0].users|length)!=1 then unsupported("导出需要单个目标和用户") else . end |
    .settings.vnext[0] |= only(["address","port","users"]; $mode+" vnext") |
    .settings.vnext[0].users[0] |= only(["id","email","level","encryption","flow","security","alterId"]; $mode+" user")
  else
    .settings |= only(["servers"]; $mode+" settings") |
    if (.settings.servers|length)!=1 then unsupported("导出需要单个服务器") else . end |
    .settings.servers[0] |= only(["address","port","password","method","email","level","uot","UoTVersion"]; $mode+" server")
  end;
def stream_options:
  only(["network","security","tlsSettings","realitySettings","rawSettings","tcpSettings","wsSettings","grpcSettings","httpupgradeSettings","xhttpSettings","kcpSettings","hysteriaSettings","masqueSettings","xdriveSettings","finalmask"]; $mode+" streamSettings") |
  if $mode!="uri" and (.finalmask // {}|length)>0 then unsupported($mode+" 不支持 Xray finalmask；请使用原生 Xray JSON") else . end;
# Settings a client can lose without changing what goes over the wire: local
# tuning (mKCP capacities and windows, the WebSocket ping interval) and options
# only the server acts on. Dropping them keeps the node exportable; everything
# else a format cannot express still makes the export refuse the node.
def drop_local:
  (if .wsSettings!=null then .wsSettings |= del(.heartbeatPeriod) else . end)
  | (if .kcpSettings!=null then .kcpSettings |= del(.uplinkCapacity,.downlinkCapacity,.cwndMultiplier,.maxSendingWindow,.congestion,.readBufferSize,.writeBufferSize) else . end)
  | (if .hysteriaSettings!=null then .hysteriaSettings |= del(.udpIdleTimeout) else . end)
  | (if .xhttpSettings!=null and (.xhttpSettings|type)=="object" then .xhttpSettings |= del(.scMaxBufferedPosts,.scStreamUpServerSecs,.serverMaxHeaderBytes,.noSSEHeader) else . end);
def common($o):
  ($o.streamSettings // {} | (if $mode=="xray" then . else drop_local end) | stream_options) as $s |
  (if ($o.protocol|IN("vless","vmess")) then ($o.settings.vnext[0]) as $v | ($v.users[0]) as $u |
     {server:$v.address,port:$v.port,uuid:$u.id,encryption:($u.encryption // "none"),flow:($u.flow // ""),cipher:($u.security // "auto")}
   else ($o.settings.servers[0]) as $v |
     {server:$v.address,port:$v.port,password:$v.password,method:($v.method // ""),encryption:"none",flow:""} end)
  + {protocol:$o.protocol,network:(if ($s.network // "raw")=="tcp" then "raw" else ($s.network // "raw") end),security:($s.security // "none"),stream:$s};
def hostport($c): (if $c.server|contains(":") then "["+$c.server+"]" else $c.server end)+":"+($c.port|tostring);
def qs: to_entries|map((.key|@uri)+"="+(.value|tostring|@uri))|join("&");
def uri_tls($c):
  if $c.security=="none" then {} elif $c.security=="tls" then
    ($c.stream.tlsSettings // {} | only(["serverName","fingerprint","alpn","allowInsecure","echConfigList","verifyPeerCertByName","pinnedPeerCertSha256","cipherSuites"]; "VLESS URI TLS")) as $t |
    {sni:$t.serverName,fp:$t.fingerprint,alpn:(if $t.alpn==null then null else $t.alpn|join(",") end),
     ech:$t.echConfigList,vcn:$t.verifyPeerCertByName,
     pcs:(if $t.pinnedPeerCertSha256==null then null elif ($t.pinnedPeerCertSha256|type)=="array" then $t.pinnedPeerCertSha256|join(",") else $t.pinnedPeerCertSha256 end),cs:$t.cipherSuites} | compact
  elif $c.security=="reality" then
    ($c.stream.realitySettings // {} | only(["serverName","fingerprint","publicKey","password","shortId","spiderX","mldsa65Verify","show"]; "VLESS URI Reality")) as $r |
    {sni:$r.serverName,fp:$r.fingerprint,pbk:($r.password // $r.publicKey),sid:($r.shortId // ""),spx:$r.spiderX,pqv:$r.mldsa65Verify} | compact
  else unsupported("VLESS URI 不支持此 security") end;
def uri_transport($c):
  if $c.network=="raw" then
    ($c.stream.rawSettings // $c.stream.tcpSettings // {} | only(["header"]; "VLESS URI TCP")) as $r |
    if ($r.header.type // "none")=="none" then {} else
      ($r.header | only(["type","request"]; "VLESS URI TCP header")) as $h |
      ($h.request // {} | only(["path","headers"]; "VLESS URI TCP request")) as $q |
      ($q.headers // {} | only(["Host","host"]; "VLESS URI TCP headers")) as $headers |
      if $h.type!="http" then unsupported("VLESS URI 不支持此 TCP header") else
      {headerType:"http",path:(($q.path // ["/"])|join(",")),host:(($headers.Host // $headers.host // [])|join(","))} end end
  elif ($c.network|IN("ws","httpupgrade")) then
    ($c.stream[if $c.network=="ws" then "wsSettings" else "httpupgradeSettings" end] // {} |
      only(["host","path","headers"]; "VLESS URI "+$c.network)) as $w |
    ($w.headers // {} | only(["Host","host"]; "VLESS URI headers")) as $headers |
    {path:($w.path // "/"),host:($w|request_host)}
  elif $c.network=="grpc" then
    ($c.stream.grpcSettings // {} | only(["serviceName","authority","multiMode"]; "VLESS URI gRPC")) as $g |
    {serviceName:($g.serviceName // ""),authority:$g.authority,mode:(if $g.multiMode==true then "multi" else "gun" end)} | compact
  elif $c.network=="xhttp" then
    ($c.stream.xhttpSettings // {}) as $x |
    (if ($x.extra|type)=="string" then $x.extra|fromjson else ($x.extra // {}) end) as $extra |
    (($x|del(.extra)) * $extra) as $effective |
    {path:($effective.path // "/"),host:($effective|request_host),mode:($effective.mode // "auto"),
     extra:($effective|del(.path,.host,.mode)|if .=={} then null else tojson end)} | compact
  elif $c.network=="kcp" then
    ($c.stream.kcpSettings // {} | only(["seed","header","mtu","tti"]; "VLESS URI mKCP")) as $k |
    {seed:$k.seed,headerType:($k.header.type // "none"),mtu:$k.mtu,tti:$k.tti}|compact
  else unsupported("此传输没有可完整表达的 VLESS URI；请使用原生 Xray JSON") end;
def uri_vless($c):
  ({encryption:$c.encryption,security:$c.security,type:(if $c.network=="raw" then "tcp" else $c.network end)} +
    (if $c.flow=="" then {} else {flow:$c.flow} end) +
    (if $packet_encoding=="" then {} else {packetEncoding:$packet_encoding} end) + uri_tls($c) + uri_transport($c) +
    (if ($c.stream.finalmask // {}|length)>0 then {fm:($c.stream.finalmask|tojson)} else {} end)) as $query |
  "vless://"+($c.uuid|@uri)+"@"+(if $c.server|contains(":") then "["+$c.server+"]" else $c.server end)+":"+($c.port|tostring)+"?"+
    ($query|to_entries|map((.key|@uri)+"="+(.value|tostring|@uri))|join("&"))+"#"+($name|@uri);
def uri($c):
  if $c.protocol=="vless" then uri_vless($c)
  elif $c.protocol=="trojan" then
    ({security:$c.security,type:(if $c.network=="raw" then "tcp" else $c.network end)} + uri_tls($c) + uri_transport($c)) as $q |
    "trojan://"+($c.password|@uri)+"@"+hostport($c)+"?"+($q|qs)+"#"+($name|@uri)
  elif $c.protocol=="vmess" then
    # v2rayN vmess:// JSON link.
    (uri_tls($c) + uri_transport($c)) as $q |
    {v:"2",ps:$name,add:$c.server,port:($c.port|tostring),id:$c.uuid,aid:"0",scy:$c.cipher,
     net:(if $c.network=="raw" then "tcp" else $c.network end),type:($q.headerType // $q.mode // "none"),
     host:($q.host // ""),path:($q.path // $q.serviceName // ""),tls:(if $c.security=="none" then "" else $c.security end),
     sni:($q.sni // ""),alpn:($q.alpn // ""),fp:($q.fp // "")}
    | "vmess://"+(tojson|@base64)
  elif $c.protocol=="shadowsocks" then
    if $c.network!="raw" or $c.security!="none" then unsupported("Shadowsocks 分享链接只能表达 RAW 且无 TLS 的配置；请使用原生 Xray JSON") else
    "ss://"+(($c.method+":"+$c.password)|@base64|gsub("=+$";""))+"@"+hostport($c)+"#"+($name|@uri) end
  else unsupported("未知协议") end;
def singbox_tls($c):
  if $c.security=="none" then {} elif $c.security=="tls" then
    ($c.stream.tlsSettings // {} | only(["serverName","fingerprint","alpn","allowInsecure","minVersion","maxVersion","cipherSuites"]; "sing-box TLS")) as $t |
    {tls:({enabled:true,server_name:$t.serverName,alpn:$t.alpn,insecure:$t.allowInsecure,min_version:$t.minVersion,max_version:$t.maxVersion,
      cipher_suites:(if ($t.cipherSuites // "")=="" then null else $t.cipherSuites|split(":") end),
      utls:(if ($t.fingerprint // "")|IN("","unsafe") then null else {enabled:true,fingerprint:$t.fingerprint} end)}|compact)}
  elif $c.security=="reality" then
    # Xray >= 26.9.8 REALITY servers reject ClientHellos without an
    # X25519MLKEM768 key share; sing-box does not send one (sing-box#4520).
    (($core_version|split(".")|map(tonumber? // 0)) as $v | ($v[0]*10000+$v[1]*100+$v[2]) >= 260908) as $pq_required |
    if $pq_required then unsupported("Xray " + $core_version + " 的 REALITY 要求客户端携带 X25519MLKEM768，sing-box 目前不支持（sing-box#4520）；请使用 Xray 内核客户端（v2rayN、v2rayNG 等）或 mihomo") else . end |
    ($c.stream.realitySettings // {} | only(["serverName","fingerprint","publicKey","password","shortId","spiderX","show"]; "sing-box Reality")) as $r |
    if ($r.spiderX // "")!="" and $r.spiderX!="/" then unsupported("sing-box 无法表达自定义 Reality spiderX；请使用原生 Xray JSON") else
    {tls:{enabled:true,server_name:($r.serverName // ""),utls:{enabled:true,fingerprint:($r.fingerprint // "chrome")},reality:{enabled:true,public_key:($r.password // $r.publicKey),short_id:($r.shortId // "")}}} end
  else unsupported("sing-box 不支持此 security") end;
def singbox_transport($c):
  if $c.network=="raw" then
    ($c.stream.rawSettings // $c.stream.tcpSettings // {} | only(["header"]; "sing-box TCP")) as $r |
    if ($r.header // {type:"none"})!={type:"none"} and ($r.header // {})!={} then unsupported("sing-box 无法表达 Xray TCP header；请使用原生 Xray JSON") else {} end
  elif $c.network=="ws" then
    ($c.stream.wsSettings // {} | only(["host","path","headers"]; "sing-box WebSocket")) as $w | ($w|ws_path) as $p |
    {transport:({type:"ws",path:$p.path,headers:($w|ws_headers)} + (if $p.early>0 then {max_early_data:$p.early,early_data_header_name:"Sec-WebSocket-Protocol"} else {} end))}
  elif $c.network=="httpupgrade" then
    ($c.stream.httpupgradeSettings // {} | only(["host","path","headers"]; "sing-box HTTPUpgrade")) as $h |
    {transport:{type:"httpupgrade",host:($h|request_host),path:($h.path // "/"),headers:($h.headers // {})}}
  elif $c.network=="grpc" then
    ($c.stream.grpcSettings // {} | only(["serviceName","authority","multiMode","idle_timeout","health_check_timeout","permit_without_stream"]; "sing-box gRPC")) as $g |
    if $g.multiMode==true then unsupported("sing-box 不支持 Xray gRPC multiMode；请使用原生 Xray JSON")
    elif ($g.authority // "")!="" and $g.authority!=($c.stream.tlsSettings.serverName // $c.stream.realitySettings.serverName // $c.server) then
      unsupported("sing-box 无法独立设置 gRPC authority；请使用原生 Xray JSON")
    else {transport:({type:"grpc",service_name:($g.serviceName // ""),permit_without_stream:$g.permit_without_stream,
      idle_timeout:(if ($g.idle_timeout // 0)>0 then ($g.idle_timeout|tostring)+"s" else null end),
      ping_timeout:(if ($g.health_check_timeout // 0)>0 then ($g.health_check_timeout|tostring)+"s" else null end)}|compact)} end
  else unsupported("当前 sing-box 不支持此 Xray 传输；请使用 Xray 或兼容的 mihomo") end;
def singbox($c):
  if $c.encryption!="none" then unsupported("当前 sing-box 不支持 VLESS Encryption；请使用 Xray 或支持该特性的 mihomo") else
  ({tag:$name,server:$c.server,server_port:$c.port} +
    (if $c.protocol=="vless" then {type:"vless",uuid:$c.uuid}
       + (if $c.flow=="" then {} else {flow:$c.flow} end)
       + (if $packet_encoding=="" then {} else {packet_encoding:(if $packet_encoding=="none" then "" else $packet_encoding end)} end)
     elif $c.protocol=="vmess" then {type:"vmess",uuid:$c.uuid,security:$c.cipher,alter_id:0}
     elif $c.protocol=="trojan" then {type:"trojan",password:$c.password}
     else (if $c.network!="raw" or $c.security!="none" then unsupported("sing-box Shadowsocks 不支持 Xray 传输或 TLS；请使用 Xray 或 mihomo") else . end)
       | {type:"shadowsocks",method:$c.method,password:$c.password} end) +
    (if $c.protocol=="shadowsocks" then {} else singbox_tls($c) + singbox_transport($c) end)) end;
def mihomo_tls($c):
  if $c.security=="none" then {tls:false} elif $c.security=="tls" then
    ($c.stream.tlsSettings // {} | only(["serverName","fingerprint","alpn","allowInsecure","pinnedPeerCertSha256"]; "mihomo TLS")) as $t |
    ($t.pinnedPeerCertSha256 // null | if .==null then null elif type=="array" then join(",") else . end) as $pin |
    if $pin!=null and ($pin|contains(",")) then unsupported("mihomo 只能固定一个证书指纹；请使用原生 Xray JSON") else . end |
    {tls:true,servername:$t.serverName,alpn:$t.alpn,"skip-cert-verify":$t.allowInsecure,
     fingerprint:(if $pin==null then null else ($pin|ascii_downcase|gsub(":";"")) end),
     "client-fingerprint":(if $t.fingerprint=="unsafe" then null else $t.fingerprint end)}|compact
  elif $c.security=="reality" then
    ($c.stream.realitySettings // {} | only(["serverName","fingerprint","publicKey","password","shortId","spiderX","show"]; "mihomo Reality")) as $r |
    if ($r.spiderX // "")!="" and $r.spiderX!="/" then unsupported("mihomo 无法表达自定义 Reality spiderX；请使用原生 Xray JSON") else
    {tls:true,servername:($r.serverName // ""),"client-fingerprint":($r.fingerprint // "chrome"),
     "reality-opts":{"public-key":($r.password // $r.publicKey),"short-id":($r.shortId // ""),"support-x25519mlkem768":true}} end
  else unsupported("mihomo 不支持此 security") end;
def xmux:
  mapped({maxConcurrency:"max-concurrency",maxConnections:"max-connections",cMaxReuseTimes:"c-max-reuse-times",hMaxRequestTimes:"h-max-request-times",hMaxReusableSecs:"h-max-reusable-secs",hKeepAlivePeriod:"h-keep-alive-period"};"mihomo XHTTP xmux") |
  with_entries(if .key!="h-keep-alive-period" then .value|=tostring else . end);
def xhttp_mihomo:
  (if (.extra|type)=="string" then .extra|fromjson else (.extra // {}) end) as $extra |
  ((del(.extra)) * $extra) |
  only(["path","host","mode","headers","noGRPCHeader","xPaddingBytes","xPaddingObfsMode","xPaddingKey","xPaddingHeader","xPaddingPlacement","xPaddingMethod","uplinkHTTPMethod","sessionIDPlacement","sessionPlacement","sessionIDKey","sessionKey","sessionIDTable","sessionTable","sessionIDLength","sessionLength","seqPlacement","seqKey","uplinkDataPlacement","uplinkDataKey","uplinkChunkSize","scMaxEachPostBytes","scMinPostsIntervalMs","xmux","downloadSettings"];"mihomo XHTTP") as $x |
  ($x|del(.xmux,.downloadSettings)|mapped({path:"path",host:"host",mode:"mode",headers:"headers",noGRPCHeader:"no-grpc-header",xPaddingBytes:"x-padding-bytes",xPaddingObfsMode:"x-padding-obfs-mode",xPaddingKey:"x-padding-key",xPaddingHeader:"x-padding-header",xPaddingPlacement:"x-padding-placement",xPaddingMethod:"x-padding-method",uplinkHTTPMethod:"uplink-http-method",sessionIDPlacement:"session-placement",sessionPlacement:"session-placement",sessionIDKey:"session-key",sessionKey:"session-key",sessionIDTable:"session-table",sessionTable:"session-table",sessionIDLength:"session-length",sessionLength:"session-length",seqPlacement:"seq-placement",seqKey:"seq-key",uplinkDataPlacement:"uplink-data-placement",uplinkDataKey:"uplink-data-key",uplinkChunkSize:"uplink-chunk-size",scMaxEachPostBytes:"sc-max-each-post-bytes",scMinPostsIntervalMs:"sc-min-posts-interval-ms"};"mihomo XHTTP")) as $base |
  ($base|with_entries(if (.key|IN("x-padding-bytes","session-length","uplink-chunk-size","sc-max-each-post-bytes","sc-min-posts-interval-ms")) then .value|=tostring else . end)) +
  (if $x.xmux==null then {} else {"reuse-settings":($x.xmux|xmux)} end) +
  (if $x.downloadSettings==null then {} else
    ($x.downloadSettings | only(["address","port","network","security","tlsSettings","realitySettings","xhttpSettings"];"mihomo XHTTP downloadSettings")) as $d |
    if ($d.network // "xhttp")!="xhttp" then unsupported("mihomo XHTTP downloadSettings 仅支持 xhttp") else
      ($d.xhttpSettings // {}|xhttp_mihomo) as $nested |
      if $nested.mode!=null or $nested."download-settings"!=null then unsupported("mihomo XHTTP downloadSettings 无法表达独立 mode 或嵌套下载设置") else
      {"download-settings":($nested + {server:$d.address,port:$d.port} +
        (if $d.security==null then {} else mihomo_tls({security:$d.security,stream:$d}) end)|compact)} end end end);
def mihomo_transport($c):
  if $c.network=="raw" then
    ($c.stream.rawSettings // $c.stream.tcpSettings // {} | only(["header"];"mihomo TCP")) as $r |
    if ($r.header.type // "none")=="none" then {network:"tcp"} else
      ($r.header|only(["type","request"];"mihomo TCP header")) as $h |
      ($h.request // {}|only(["method","path","headers"];"mihomo TCP request")) as $q |
      if $h.type!="http" then unsupported("mihomo 不支持此 TCP header") else {network:"http","http-opts":({method:$q.method,path:$q.path,headers:$q.headers}|compact)} end end
  elif ($c.network|IN("ws","httpupgrade")) then
    ($c.stream[if $c.network=="ws" then "wsSettings" else "httpupgradeSettings" end] // {} | only(["host","path","headers"];"mihomo "+$c.network)) as $w |
    ($w|ws_path) as $p |
    {network:"ws","ws-opts":({path:$p.path,headers:($w|ws_headers)} +
      (if $p.early>0 then {"max-early-data":$p.early,"early-data-header-name":"Sec-WebSocket-Protocol"} else {} end) +
      (if $c.network=="httpupgrade" then {"v2ray-http-upgrade":true} else {} end))}
  elif $c.network=="grpc" then
    ($c.stream.grpcSettings // {} | only(["serviceName","authority","multiMode","user_agent"];"mihomo gRPC")) as $g |
    if $g.multiMode==true then unsupported("mihomo 不支持 Xray gRPC multiMode；请使用原生 Xray JSON")
    elif ($g.authority // "")!="" and $g.authority!=($c.stream.tlsSettings.serverName // $c.stream.realitySettings.serverName // $c.server) then
      unsupported("mihomo 无法独立设置 gRPC authority；请使用原生 Xray JSON")
    else {network:"grpc","grpc-opts":({"grpc-service-name":($g.serviceName // ""),"grpc-user-agent":$g.user_agent}|compact)} end
  elif $c.network=="xhttp" then {network:"xhttp","xhttp-opts":($c.stream.xhttpSettings // {}|xhttp_mihomo)}
  else unsupported("mihomo VLESS 不支持此传输；请使用原生 Xray JSON") end;
def mihomo($c):
  if $c.protocol=="vless" and $packet_encoding=="none" then unsupported("mihomo VLESS 未提供关闭 packet encoding 的对应选项；请使用原生 Xray JSON") else
  ({name:$name,server:$c.server,port:$c.port,udp:true} +
    (if $c.protocol=="vless" then {type:"vless",uuid:$c.uuid,encryption:$c.encryption}
       + (if $c.flow=="" then {} else {flow:$c.flow} end)
       + (if $packet_encoding=="" then {} else {"packet-encoding":$packet_encoding} end)
     elif $c.protocol=="vmess" then {type:"vmess",uuid:$c.uuid,alterId:0,cipher:$c.cipher}
     elif $c.protocol=="trojan" then
       # Verified with mihomo v1.19.34: reality-opts is ignored for trojan.
       (if $c.security=="reality" then unsupported("mihomo 的 Trojan 不支持 REALITY（实测 v1.19.34 未启用）；请使用 Xray 内核客户端") else . end)
       | {type:"trojan",password:$c.password}
     else (if $c.network!="raw" or $c.security!="none" then unsupported("mihomo Shadowsocks 不支持 Xray 传输或 TLS；请使用原生 Xray JSON") else . end)
       | {type:"ss",cipher:$c.method,password:$c.password} end) +
    (if $c.protocol=="shadowsocks" then {} else mihomo_tls($c) + mihomo_transport($c) end)) end;
try (root_options | common(.) as $c |
  {ok:true,value:(if $mode=="uri" then uri($c) elif $mode=="singbox" then singbox($c) elif $mode=="mihomo" then mihomo($c) else unsupported("未知 VLESS 导出格式") end)})
catch {ok:false,reason:(if type=="object" and has("sb_reason") then .sb_reason else "此格式无法安全转换当前参数；请使用原生 Xray JSON并检查字段类型。" end)}
