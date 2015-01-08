open Ctypes
open Foreign

type ip_option =
  | IP_MULTICAST_IF
  | IP_MULTICAST_TTL
  | IP_MULTICAST_LOOP
  | IP_ADD_MEMBERSHIP
  | IP_DROP_MEMBERSHIP

type ipv6_option =
  | IPV6_JOIN_GROUP
  | IPV6_LEAVE_GROUP
  | IPV6_MULTICAST_HOPS
  | IPV6_MULTICAST_IF
  | IPV6_MULTICAST_LOOP
  | IPV6_UNICAST_HOPS
  | IPV6_V6ONLY

type level =
  | SOL_SOCKET
  | IPPROTO_IP
  | IPPROTO_IPV6
  | IPPROTO_ICMP
  | IPPROTO_RAW
  | IPPROTO_TCP
  | IPPROTO_UDP

type sa_family =
  | AF_INET
  | AF_INET6
  | AF_UNIX
  | AF_UNSPEC

type sendrecvflags =
  | MSG_CONFIRM
  | MSG_DONTROUTE
  | MSG_DONTWAIT
  | MSG_EOR
  | MSG_MORE
  | MSG_NOSIGNAL
  | MSG_OOB
  | MSG_CMSG_CLOEXEC
  | MSG_ERRQUEUE
  | MSG_PEEK
  | MSG_TRUNC
  | MSG_WAITALL


let if_nametoindex = foreign ~check_errno:true "if_nametoindex" (string @-> returning int)
external swap16 : int -> int = "%bswap16";;
let int_of_file_descr (fd:Unix.file_descr) : int = Obj.magic fd
external int_of_level : level -> int = "c_int_of_level"
external int_of_ip_option : ip_option -> int = "c_int_of_ip_option"
external int_of_ipv6_option : ipv6_option -> int = "c_int_of_ipv6_option"
external int_of_sa_family : sa_family -> int = "c_int_of_sa_family"
external int_of_sendrecvflags : sendrecvflags -> int = "c_int_of_sendrecvflags"

let int_of_flags flags = List.fold_left (fun acc f -> acc lor int_of_sendrecvflags f) 0 flags

module In_addr = struct
  type t
  let t : t structure typ = structure "in_addr"
  let s_addr = field t "s_addr" int32_t
  let () = seal t
  let make v4addr =
    let s = make t in
    let v4addr = Ipaddr.V4.to_bytes v4addr in
    let v4addr = EndianString.LittleEndian.get_int32 v4addr 0 in
    setf s s_addr v4addr;
    s
end

module In6_addr = struct
  type t
  let t : t structure typ = structure "in6_addr"
  let s6_addr = field t "s6_addr" @@ array 16 char
  let () = seal t
  let make v6addr =
    let s = make t in
    let carr = getf s s6_addr in
    let v6addr_bytes = Ipaddr.V6.to_bytes v6addr in
    for i = 0 to 15 do
      CArray.unsafe_set carr i @@ Bytes.unsafe_get v6addr_bytes i
    done; s
end

module Sockaddr = struct
  type t
  let t : t structure typ = structure "sockaddr"
  let sa_family = field t "sa_family" uint
  let sa_data = field t "sa_data" (array 14 uint8_t)
  let () = seal t
end

module Sockaddr_in = struct
  type t
  let t : t structure typ = structure "sockaddr_in"
  let sin_family = field t "sin_family" uint16_t
  let sin_port = field t "sin_port" uint16_t
  let sin_addr = field t "sin_addr" In_addr.t
  let sin_zero = field t "sin_zero" (array 8 char)
  let () = seal t
  let make addr port =
    let s = make t in
    setf s sin_family (int_of_sa_family AF_INET |> Unsigned.UInt16.of_int);
    setf s sin_port (port |> swap16 |> Unsigned.UInt16.of_int);
    setf s sin_addr (In_addr.make addr);
    s
end

module Sockaddr_in6 = struct
  type t
  let t : t structure typ = structure "sockaddr_in6"
  let sin6_family = field t "sin6_family" uint16_t
  let sin6_port = field t "sin6_port" uint16_t
  let sin6_flowinfo = field t "sin6_flowinfo" uint32_t
  let sin6_addr = field t "sin6_addr" In6_addr.t
  let sin6_scope_id = field t "sin6_scope_id" uint32_t
  let () = seal t
  let make ?iface ?(flowinfo=0) v6addr port =
    let s = make t in
    setf s sin6_family (int_of_sa_family AF_INET6 |> Unsigned.UInt16.of_int);
    setf s sin6_port (port |> swap16 |> Unsigned.UInt16.of_int);
    setf s sin6_flowinfo (flowinfo |> Int32.of_int |> Unsigned.UInt32.of_int32);
    setf s sin6_addr (In6_addr.make v6addr);
    (match iface with
    | None -> setf s sin6_scope_id (Unsigned.UInt32.zero)
    | Some name -> setf s sin6_scope_id (if_nametoindex name |> Unsigned.UInt32.of_int));
    s
end

module Ip_mreq = struct
  type t
  let t : t structure typ = structure "ip_mreq"
  let imr_multiaddr = field t "imr_multiaddr" In_addr.t
  let imr_interface = field t "imr_interface" In_addr.t
  let () = seal t
  let make ?iface_addr v4addr =
    let s = make t in
    setf s imr_multiaddr (In_addr.make v4addr);
    (match iface_addr with
    | None -> setf s imr_interface (In_addr.make Ipaddr.V4.any)
    | Some addr -> setf s imr_interface (In_addr.make addr));
    s
end

module Ipv6_mreq = struct
  type t
  let t : t structure typ = structure "ipv6_mreq"
  let ipv6mr_multiaddr = field t "ipv6mr_multiaddr" In6_addr.t
  let ipv6mr_interface = field t "ipv6mr_interface" int
  let () = seal t
  let make ?iface v6addr =
    let s = make t in
    (match iface with
     | None -> setf s ipv6mr_interface 0
     | Some name -> setf s ipv6mr_interface (if_nametoindex name));
    setf s ipv6mr_multiaddr (In6_addr.make v6addr);
    s
end

let _send = foreign ~check_errno:true "send" (int @-> string @-> size_t @-> int @-> returning int)
let _recv = foreign ~check_errno:true "recv" (int @-> string @-> size_t @-> int @-> returning int)

let sendto4 = foreign ~check_errno:true "sendto" (int @-> string @-> size_t @-> int
                                                 @-> ptr Sockaddr_in.t @-> size_t @-> returning int)
let sendto6 = foreign ~check_errno:true "sendto" (int @-> string @-> size_t @-> int
                                                 @-> ptr Sockaddr_in.t @-> size_t @-> returning int)

let recvfrom4 = foreign ~check_errno:true "recvfrom" (int @-> string @-> size_t @-> int
                                                      @-> ptr Sockaddr_in6.t @-> size_t @-> returning int)
let recvfrom6 = foreign ~check_errno:true "recvfrom" (int @-> string @-> size_t @-> int
                                                      @-> ptr Sockaddr_in6.t @-> size_t @-> returning int)

let setsockopt = foreign ~check_errno:true "setsockopt" (int @-> int @-> int @-> ptr void @-> int @-> returning int)
let getsockopt = foreign ~check_errno:true "getsockopt" (int @-> int @-> int @-> ptr void @-> ptr int @-> returning int)
let _bind = foreign ~check_errno:true "bind" (int @-> ptr Sockaddr_in6.t @-> int @-> returning int)
let _connect = foreign ~check_errno:true "connect" (int @-> ptr Sockaddr_in6.t @-> int @-> returning int)

let setsockopt_int fd level option i =
  let (_:int) = setsockopt (int_of_file_descr fd) level option
      (allocate int i |> to_voidp) (sizeof int) in ()

let setsockopt_uint fd level option ui =
  let (_:int) = setsockopt (int_of_file_descr fd) level option
      (allocate uint Unsigned.UInt.(of_int ui) |> to_voidp) (sizeof uint) in ()

module IP = struct
  let send fd buf pos len flags =
    _send
      (int_of_file_descr fd)
      (Bytes.sub buf pos len)
      (Unsigned.Size_t.of_int len)
      (int_of_flags flags)

  let send_substring fd buf pos len flags =
    _send
      (int_of_file_descr fd)
      (Bytes.sub buf pos len)
      (Unsigned.Size_t.of_int len)
      (int_of_flags flags)

  let recv fd buf pos len flags =
    if (pos < 0 || len < 0 || pos + len > Bytes.length buf)
    then invalid_arg "bounds";
    _recv
      (int_of_file_descr fd)
      buf (Unsigned.Size_t.of_int pos) (int_of_flags flags)

  module V4 = struct
    let bind sock v4addr port =
      Unix.(bind sock @@ ADDR_INET (Ipaddr_unix.V4.to_inet_addr v4addr, port))

    let connect sock v4addr port =
      Unix.(connect sock @@ ADDR_INET (Ipaddr_unix.V4.to_inet_addr v4addr, port))

    let membership ?iface_addr fd v4addr direction =
      let s = Ip_mreq.make ?iface_addr v4addr in
      let direction = match direction with
        | `Join -> IP_ADD_MEMBERSHIP
        | `Leave -> IP_DROP_MEMBERSHIP in
      let ret = setsockopt
          (int_of_file_descr fd)
          (int_of_level IPPROTO_IP)
          (int_of_ip_option direction)
          (addr s |> to_voidp)
          (sizeof Ip_mreq.t)
      in ignore (ret:int)

    let mcast_outgoing_iface fd iface =
      setsockopt_int fd (int_of_level IPPROTO_IP)
        (int_of_ip_option IP_MULTICAST_IF) (if_nametoindex iface)

    let mcast_loop fd b =
      setsockopt_uint fd (int_of_level IPPROTO_IP)
        (int_of_ip_option IP_MULTICAST_LOOP) (if b then 1 else 0)

    let mcast_hops fd n =
      setsockopt_int fd (int_of_level IPPROTO_IP)
        (int_of_ip_option IP_MULTICAST_TTL) n
  end

  module V6 = struct
    let bind ?iface ?(flowinfo=0) sock v6addr port =
      let saddr_in6 = Sockaddr_in6.make ?iface ~flowinfo v6addr port in
      let ret = _bind
          (int_of_file_descr sock)
          (addr saddr_in6)
          (sizeof Sockaddr_in6.t)
      in ignore (ret:int)

    let connect ?iface ?(flowinfo=0) sock v6addr port =
      let saddr_in6 = Sockaddr_in6.make ?iface ~flowinfo v6addr port in
      let ret = _connect
          (int_of_file_descr sock)
          (addr saddr_in6)
          (sizeof Sockaddr_in6.t)
      in ignore (ret:int)

    let membership ?iface fd v6addr direction =
      let s = Ipv6_mreq.make ?iface v6addr in
      let direction = match direction with
        | `Join -> IPV6_JOIN_GROUP
        | `Leave -> IPV6_LEAVE_GROUP in
      let ret = setsockopt
          (int_of_file_descr fd)
          (int_of_level IPPROTO_IPV6)
          (int_of_ipv6_option direction)
          (addr s |> to_voidp)
          (sizeof Ipv6_mreq.t)
      in ignore (ret:int)

    let mcast_outgoing_iface fd iface =
      setsockopt_int fd (int_of_level IPPROTO_IPV6)
        (int_of_ipv6_option IPV6_MULTICAST_IF) (if_nametoindex iface)

    let mcast_loop fd b =
      setsockopt_uint fd (int_of_level IPPROTO_IPV6)
        (int_of_ipv6_option IPV6_MULTICAST_LOOP) (if b then 1 else 0)

    let mcast_hops fd n =
      setsockopt_int fd (int_of_level IPPROTO_IP)
        (int_of_ipv6_option IPV6_MULTICAST_HOPS) n

    let ucast_hops fd n =
      setsockopt_int fd
        (int_of_level IPPROTO_IPV6)
        (int_of_ipv6_option IPV6_UNICAST_HOPS) n
  end
end

module U = struct
  let bind ?iface ?(flowinfo=0) fd sa = match sa with
    | Unix.ADDR_UNIX a -> Unix.bind fd sa
    | Unix.ADDR_INET (h, p) ->
      match Ipaddr_unix.V6.of_inet_addr h with
      | None -> Unix.bind fd sa
      | Some v6addr -> IP.V6.bind ?iface ~flowinfo fd v6addr p


  let connect ?iface ?(flowinfo=0) fd sa = match sa with
    | Unix.ADDR_UNIX a -> Unix.connect fd sa
    | Unix.ADDR_INET (h, p) ->
      match Ipaddr_unix.V6.of_inet_addr h with
      | None -> Unix.connect fd sa
      | Some v6addr -> IP.V6.connect ?iface ~flowinfo fd v6addr p

  let membership6 ?iface fd ipaddr direction =
    match Ipaddr_unix.of_inet_addr ipaddr with
    | Ipaddr.V6 v6addr -> IP.V6.membership ?iface fd v6addr direction
    | _ -> invalid_arg "membership6"
end
