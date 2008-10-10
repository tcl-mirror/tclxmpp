# ntlm.tcl --
#
#       This file implements NTLM Authentication messages in Tcl.
#       This module is based on Mozilla NTLM authenticattion module and
#       documentation from http://davenport.sourceforge.net/ntlm.html
#
# Copyright (c) 2004-2008 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require des
package require md4
package require md5
package require base64

package provide ntlm 1.0

namespace eval NTLM {
    namespace export new free type1Message parseType2Message type3Messasge

    # NTLM flags.
    array set NTLM {
          NegotiateUnicode             0x00000001
          NegotiateOEM                 0x00000002
          RequestTarget                0x00000004
          Unknown1                     0x00000008
          NegotiateSign                0x00000010
          NegotiateSeal                0x00000020
          NegotiateDatagramStyle       0x00000040
          NegotiateLanManagerKey       0x00000080
          NegotiateNetware             0x00000100
          NegotiateNTLMKey             0x00000200
          Unknown2                     0x00000400
          Unknown3                     0x00000800
          NegotiateDomainSupplied      0x00001000
          NegotiateWorkstationSupplied 0x00002000
          NegotiateLocalCall           0x00004000
          NegotiateAlwaysSign          0x00008000
          TargetTypeDomain             0x00010000
          TargetTypeServer             0x00020000
          TargetTypeShare              0x00040000
          NegotiateNTLM2Key            0x00080000
          RequestInitResponse          0x00100000
          RequestAcceptResponse        0x00200000
          RequestNonNTSessionKey       0x00400000
          NegotiateTargetInfo          0x00800000
          Unknown4                     0x01000000
          Unknown5                     0x02000000
          Unknown6                     0x04000000
          Unknown7                     0x08000000
          Unknown8                     0x10000000
          Negotiate128                 0x20000000
          NegotiateKeyExchange         0x40000000
          Negotiate56                  0x80000000
    }

    # Send these flags with our Type1 message.
    set NTLM(TYPE1_FLAGS_INT) [expr {($NTLM(NegotiateUnicode) | \
                                      $NTLM(NegotiateOEM)     | \
                                      $NTLM(RequestTarget)    | \
                                      $NTLM(NegotiateNTLMKey) | \
                                      $NTLM(NegotiateNTLM2Key))}]
    set NTLM(TYPE1_FLAGS) [binary format i $NTLM(TYPE1_FLAGS_INT)]

    # Markers and signatures.
    array set NTLM [list \
        SIGNATURE    [binary format a8 "NTLMSSP"] \
        TYPE1_MARKER [binary format i  1]         \
        TYPE2_MARKER [binary format i  2]         \
        TYPE3_MARKER [binary format i  3]         \
        LM_MAGIC     [binary format a* "KGS!@#$%"]]
}

# NTLM::new --
#
#       Allocates new NTLM token.
#
# Arguments:
#           -domain   Domain    (optional)
#           -host     Host      (optional)
#           -username Username  (optional)
#           -password Password  (optional)
#           All credentials are empty strings by default.
#
# Result:
#       A NTLM token.
#
# Side effects:
#       A new state variable in NTLM namespace is created. Also,
#       a new procedure with token name is created.

proc NTLM::new {args} {
    variable uid

    if {![info exists uid]} {
        set uid 0
    }

    set token [namespace current]::[incr uid]
    variable $token
    upvar 0 $token state

    set state(-domain) ""
    set state(-host) ""
    set state(-username) ""
    set state(-password) ""

    foreach {opt val} $args {
        switch -- $opt {
            -domain -
            -host -
            -username -
            -password {
                set state($opt) $val
            }
            default {
                return -code error "Illegal option \"$key\""
            }
        }
    }

    proc $token {cmd args} "eval {[namespace current]::\$cmd} {$token} \$args"

    return $token
}

# NTLM::free --
#
#       Frees previously allocated NTLM token.
#
# Arguments:
#       token       A previously allocated NTLM token.
#
# Result:
#       An empty string.
#
# Side effects:
#       A state variable is destroyed.

proc NTLM::free {token} {
    variable $token
    upvar 0 $token state

    catch {unset state}
    catch {rename $token ""}
    return
}

# NTLM::type1Message --
#
#       Generates NTLM Type1 message (start of the authentication process).
#
# Arguments:
#       token       A NTLM token.
#
# Result:
#       A BASE64 encoded NTLM Type1 message.
#
# Side effects:
#       None.

proc NTLM::type1Message {token} {
    variable NTLM
    variable $token
    upvar 0 $token state

    # two empty strings correspond to security buffers for empty domain and
    # workstation data blocks
    set msg1 [binary format a*a*a*a8a8   \
                     $NTLM(SIGNATURE)    \
                     $NTLM(TYPE1_MARKER) \
                     $NTLM(TYPE1_FLAGS)  \
                     "" ""]
    return [string map {\n {}} [base64::encode $msg1]]
}

# NTLM::parseType2Message --
#
#       Parses NTLM Type2 message (server response).
#
# Arguments:
#       token               A NTLM token.
#       -message Message    (required) A server Type2 message.
#
# Result:
#       Empty string in case of success or error if something goes wrong.
#
# Side effects:
#       A target, challenge and negotiated flags are stored in state variable.

proc NTLM::parseType2Message {token args} {
    variable NTLM
    variable $token
    upvar 0 $token state

    foreach {opt val} $args {
        switch -- $opt {
            -message {
                set msg $val
            }
            default {
                return -code error "Illegal option \"$key\""
            }
        }
    }
    if {![info exists msg]} {
        return -code error "Message to parse isn't provided"
    }

    set msg2 [base64::decode $msg]

    # checking NTLM signature
    if {![string equal [string range $msg2 0 7] $NTLM(SIGNATURE)]} {
        return -code error "Invalid NTLM protocol signature"
    }

    # checking type2 message marker
    if {![string equal [string range $msg2 8 11] $NTLM(TYPE2_MARKER)]} {
        return -code error "Invalid NTLM message type (must be equal to 2)"
    }

    # storing target name (NTLM realm)
    binary scan [string range $msg2 12 13] s target_len
    binary scan [string range $msg2 16 19] i target_offset
    set state(target) [string range $msg2 $target_offset \
                              [expr {$target_offset + $target_len - 1}]]

    # storing negotiated flags
    binary scan [string range $msg2 20 23] i state(flags)

    # storing and returning challenge
    set state(challenge) [string range $msg2 24 31]

    return
}

# NTLM::type3Message --
#
#       Generates NTLM Type3 message (the end of the authentication process).
#
# Arguments:
#       token       A NTLM token after parsing Type2 message.
#
# Result:
#       A BASE64 encoded NTLM Type3 message.
#
# Side effects:
#       None.

proc NTLM::type3Message {token} {
    variable NTLM
    variable $token
    upvar 0 $token state

    set unicode [expr {$state(flags) & $NTLM(NegotiateUnicode)}]
    set target_type_domain [expr {$state(flags) & $NTLM(TargetTypeDomain)}]

    if {$unicode} {
        set domain [ToUnicodeLe [string toupper $state(-domain)]]
        set host [ToUnicodeLe [string toupper $state(-host)]]
        set username [ToUnicodeLe $state(-username)]
    } else {
        set domain [encoding convertto [string toupper $state(-domain)]]
        set host [encoding convertto [string toupper $state(-host)]]
        set username [encoding convertto $state(-username)]
    }
    if {$target_type_domain && ($state(-domain) == "")} {
        set domain $state(target)
    }

    set challenge $state(challenge)

    if {[expr {$state(flags) & $NTLM(NegotiateNTLM2Key)}]} {
        set rnd1 [expr {int((1<<16)*rand())}]
        set rnd2 [expr {int((1<<16)*rand())}]
        set rnd3 [expr {int((1<<16)*rand())}]
        set rnd4 [expr {int((1<<16)*rand())}]
        set random [binary format ssss $rnd1 $rnd2 $rnd3 $rnd4]

        set lm_response [binary format a24 $random]
        set session_hash [md5 [binary format a8a8 $challenge $random]]

        set ntlm_hash [NtlmHash $state(-password)]
        set ntlm_response [LmResponse $ntlm_hash $session_hash]
    } else {
        set lm_hash [LmHash $state(-password)]
        set lm_response [LmResponse $lm_hash $challenge]

        set ntlm_hash [NtlmHash $state(-password)]
        set ntlm_response [LmResponse $ntlm_hash $challenge]
    }

    # Offset of the end of header.
    set offset 64

    set offset [CreateData $domain        $offset data(domain)]
    set offset [CreateData $username      $offset data(username)]
    set offset [CreateData $host          $offset data(host)]
    set offset [CreateData $lm_response   $offset data(lm)]
    set offset [CreateData $ntlm_response $offset data(ntlm)]

    set flags [expr {$state(flags) & $NTLM(TYPE1_FLAGS_INT)}]

    set msg3 [binary format a*a*a*a*a*a*a*a8ia*a*a*a*a* \
                     $NTLM(SIGNATURE) $NTLM(TYPE3_MARKER) \
                     $data(lm) $data(ntlm) \
                     $data(domain) $data(username) $data(host) \
                     "" $flags \
                     $domain $username $host $lm_response $ntlm_response]

    return [string map {\n {}} [base64::encode $msg3]]
}

# NTLM::md5 --
#
#       Returns binary MD5 hash of specified string. This procedure is needed
#       if md5 package has version less than 2.0.
#
# Arguments:
#       str
#
# Result:
#       The binary MD5 hash.
#
# Side effects:
#       None.

proc NTLM::md5 {str} {
    if {[catch {::md5::md5 -hex $str} hash]} {
        # Old md5 package.
        set hash [::md5::md5 $str]
    }
    return [binary format H32 $hash]
}

# NTLM::CreateData --
#
#       Returns next offset (in error code) and security buffer data
#
# Arguments:
#       str
#       offset
#       dataVar
#
# Result:
#       The next offset.
#
# Side effects:
#       Variable dataVar is set to a binary value for packing into a NTLM
#       message.

proc NTLM::CreateData {str offset dataVar} {
    upvar 1 $dataVar data

    set len [string length $str]
    set data [binary format ssi $len $len $offset]
    return [expr {$offset + $len}]
}

# NTLM::LmHash --
#
#       Computes the LM hash of the given password.
#
# Arguments:
#       password        A password to hash.
#
# Result:
#       A LM hash of the given password.
#
# Side effects:
#       None.

proc NTLM::LmHash {password} {
    variable NTLM

    set password [encoding convertto [string toupper $password]]

    # pad password with zeros or truncate if it is longer than 14
    set pwd [binary format a14 $password]

    # setup two DES keys
    set key1 [MakeKey [string range $pwd 0 6]]
    set key2 [MakeKey [string range $pwd 7 13]]

    # do hash
    set res1 [DES::des -mode encode -key $key1 $NTLM(LM_MAGIC)]
    set res2 [DES::des -mode encode -key $key2 $NTLM(LM_MAGIC)]

    return [binary format a8a8 $res1 $res2]
}

# NTLM::NtlmHash --
#
#       Computes the NTLM hash of the given password.
#
# Arguments:
#       password        A password to hash.
#
# Result:
#       A NTLM hash of the given password.
#
# Side effects:
#       None.

proc NTLM::NtlmHash {password} {
    # we have to have UNICODE password
    set pw [ToUnicodeLe $password]

    # do MD4 hash
    return [md4::md4 -- $pw]
}

# NTLM::LmResponse --
#
#       Generates the LM response given a 16-byte password hash and the
#       challenge from the Type-2 message.
#
# Arguments:
#       hash        A password hash
#       challenge   A challenge.
#
# Result:
#       A LM hash (3 concatenated DES-encrypted strings).
#
# Side effects:
#       None.

proc NTLM::LmResponse {hash challenge} {
    # zero pad hash to 21 bytes
    set hash [binary format a21 $hash]
    # truncate challenge to 8 bytes
    set challenge [binary format a8 $challenge]

    set key1 [MakeKey [string range $hash 0 6]]
    set key2 [MakeKey [string range $hash 7 13]]
    set key3 [MakeKey [string range $hash 14 20]]

    set res1 [DES::des -mode encode -key $key1 $challenge]
    set res2 [DES::des -mode encode -key $key2 $challenge]
    set res3 [DES::des -mode encode -key $key3 $challenge]

    return [binary format a8a8a8 $res1 $res2 $res3]
}

# NTLM::MakeKey --
#
#       Builds 64-bit DES key from 56-bit raw key.
#
# Arguments:
#       key     A 56-bit key.
#
# Result:
#       A 64-bit DES key.
#
# Side effects:
#       None.

proc NTLM::MakeKey {key} {
    binary scan $key ccccccc k(0) k(1) k(2) k(3) k(4) k(5) k(6)
    # make numbers unsigned
    foreach i [array names k] {
        set k($i) [expr {($k($i) + 0x100) % 0x100}]
    }

    set n(0) [SetKeyParity $k(0)]
    set n(1) [SetKeyParity [expr {(($k(0) << 7) & 0xff) | ($k(1) >> 1)}]]
    set n(2) [SetKeyParity [expr {(($k(1) << 6) & 0xff) | ($k(2) >> 2)}]]
    set n(3) [SetKeyParity [expr {(($k(2) << 5) & 0xff) | ($k(3) >> 3)}]]
    set n(4) [SetKeyParity [expr {(($k(3) << 4) & 0xff) | ($k(4) >> 4)}]]
    set n(5) [SetKeyParity [expr {(($k(4) << 3) & 0xff) | ($k(5) >> 5)}]]
    set n(6) [SetKeyParity [expr {(($k(5) << 2) & 0xff) | ($k(6) >> 6)}]]
    set n(7) [SetKeyParity [expr  {($k(6) << 1) & 0xff}]]

    return [binary format cccccccc \
                   $n(0) $n(1) $n(2) $n(3) $n(4) $n(5) $n(6) $n(7)]
}

# NTLM::SetKeyParity --
#
#       Sets odd parity bit (in least significant bit position)
#       DES::des seems not to require setting parity, but...
#
# Arguments:
#       x       A byte integer.
#
# Result:
#       An integer with parity bit set, so the total number of bits set is
#       odd.
#
# Side effects:
#       None.

proc NTLM::SetKeyParity {x} {
    set xor [expr {(($x >> 7) ^ ($x >> 6) ^ ($x >> 5) ^
                    ($x >> 4) ^ ($x >> 3) ^ ($x >> 2) ^
                    ($x >> 1)) & 0x01}]
    if {$xor == 0} {
        return [expr {($x & 0xff) | 0x01}]
    } else {
        return [expr {$x & 0xfe}]
    }
}

# NTLM::ToUnicodeLe --
#
#       Converts a string to unicode in little endian byte order
#       (taken from tcllib/sasl).
#
# Arguments:
#       str     A string to convert.
#
# Result:
#       A converted to little endian byte order string.
#
# Side effects:
#       None.

proc NTLM::ToUnicodeLe {str} {
    set result [encoding convertto unicode $str]
    if {[string equal $::tcl_platform(byteOrder) "bigEndian"]} {
        set r {} ; set n 0
        while {[binary scan $result @${n}cc a b] == 2} {
            append r [binary format cc $b $a]
            incr n 2
        }
        set result $r
    }
    return $result
}

# vim:ts=8:sw=4:sts=4:et
