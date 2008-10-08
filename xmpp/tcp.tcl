# tcp.tcl --
#
#       This file is part of the XMPP library. It provides support for the
#       XMPP stream over TCP sockets.
#
# Copyright (c) 2008 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require pconnect
package require xmpp::transport
package require xmpp::xml

package provide xmpp::transport::tcp 0.1

namespace eval ::xmpp::transport::tcp {
    namespace export open abort close reset flush ip outXML outText \
                     openStream closeStream

    ::xmpp::transport::register tcp \
            -openCommand        [namespace code open]       \
            -abortCommand       [namespace code abort]      \
            -closeCommand       [namespace code close]      \
            -resetCommand       [namespace code reset]      \
            -flushCommand       [namespace code flush]      \
            -ipCommand          [namespace code ip]         \
            -outXMLCommand      [namespace code outXML]     \
            -outTextCommand     [namespace code outText]    \
            -openStreamCommand  [namespace code openStream] \
            -closeStreamCommand [namespace code closeStream]
}

# ::xmpp::transport::tcp::open --
#
#       Open TCP socket (using ::pconnect::socket), create XML parser and
#       link them together.
#
# Arguments:
#       host                        Host to connect.
#       port                        Port to connect.
#       -command              cmd0  (optional) Callback to call when TCP
#                                   connection to server (directly or through
#                                   proxy) is established. If missing then a
#                                   synchronous mode is set and function
#                                   doesn't return until connect succeded or
#                                   failed.
#       -streamHeaderCommand  cmd1  Command to call when XMPP stream header
#                                   (<stream:stream>) is received.
#       -streamTrailerCommand cmd2  Command to call when XMPP stream trailer
#                                   (</stream:stream>) is received.
#       -stanzaCommand        cmd3  Command to call when XMPP stanza is
#                                   received.
#       -eofCommand           cmd4  End-of-file callback.
#
# Result:
#       In asynchronous mode pconnect token is returned to allow to abort
#       connection process. In synchronous mode pair {socket parser} is
#       returned in case of success or error is raised if the connection is
#       failed.
#
# Side effects:
#       In synchronous mode in case of success a new TCP socket and XML parser
#       are created, in case of failure none. In asynchronous mode a call to
#       ::pconnect::socket is executed.

proc ::xmpp::transport::tcp::open {host port args} {
    variable id

    if {![info exists id]} {
        set id 0
    }

    set token [namespace current]::[incr id]
    variable $token
    upvar 0 $token state

    set state(transport) tcp

    set state(streamHeaderCmd)  #
    set state(streamTrailerCmd) #
    set state(stanzaCmd)        #
    set state(eofCmd)           #
    set newArgs                 {}

    foreach {key val} $args {
        switch -- $key {
            -command              {set cmd                     $val}
            -streamHeaderCommand  {set state(streamHeaderCmd)  $val}
            -streamTrailerCommand {set state(streamTrailerCmd) $val}
            -stanzaCommand        {set state(stanzaCmd)        $val}
            -eofCommand           {set state(eofCmd)           $val}
            default               {lappend newArgs $key $val}
        }
    }

    if {![info exists cmd]} {
        # Synchronous mode
        set state(sock) [eval [list ::pconnect::socket $host $port] $newArgs]
        Configure $token
    } else {
        # Asynchronous mode
        set state(pconnect) \
            [eval [list ::pconnect::socket $host $port] $newArgs \
                  [list -command [namespace code [list OpenAux $token $cmd]]]]
    }

    return $token
}

# ::xmpp::transport::tcp::OpenAux --
#
#       A helper procedure which is passed as a callback to ::pconnect::socket
#       call and in turn invokes a callback for [open] procedure.
#
# Arguments:
#       token               Transport token created in [open]
#       cmd                 Procedure to call with status ok or error.
#       status              Connection status (ok means success).
#       sock                TCP socket if status is ok, or error message if
#                           status is error, timeout, or abort.
#
# Result:
#       Empty string.
#
# Side effects:
#       If status is ok then a new XML parser is created. In all cases a
#       callback procedure is executed.

proc ::xmpp::transport::tcp::OpenAux {token cmd status sock} {
    variable $token
    upvar 0 $token state

    if {[string equal $status ok]} {
        unset state(pconnect)
        Configure $token
    } else {
        # Here $sock contains error message
        set token $sock
    }

    uplevel #0 $cmd [list $status $token]
    return
}

# ::xmpp::transport::tcp::Configure --
#
#       A helper procedure which creates a new XML parser and configures TCP
#       socket.
#
# Arguments:
#       token               Transport token created in [open]
#
# Result:
#       Empty string.
#
# Side effects:
#       Socket is put in non-buffering nonblocking mode with encoding UTF-8.
#       XML parser is created.

proc ::xmpp::transport::tcp::Configure {token} {
    variable $token
    upvar 0 $token state

    set state(parser) \
        [::xmpp::xml::new \
                [namespace code [list InXML $state(streamHeaderCmd)]] \
                [namespace code [list InEmpty $state(streamTrailerCmd)]] \
                [namespace code [list InXML $state(stanzaCmd)]]]

    fconfigure $state(sock) -blocking    0    \
                            -buffering   none \
                            -translation auto \
                            -encoding    utf-8

    fileevent $state(sock) readable [namespace code [list InText $token]]
    return
}

proc ::xmpp::transport::tcp::abort {token} {
    variable $token
    upvar 0 $token state

    if {[info exists state(parser)]} {
        ::xmpp::xml::free $state(parser)
    }

    set pconnect $state(pconnect)
    unset state

    # If ::pconnect::abort returns error then propagate it to the caller
    ::pconnect::abort $pconnect

    return
}

proc ::xmpp::transport::tcp::outText {token text} {
    variable $token
    upvar 0 $token state

    if {[catch {puts -nonewline $state(sock) $text} err]} {
        ::xmpp::log "error (outText) Cannot write to\
                     socket $sock: $err"
        return -1
    } else {
        # TODO
        return [string bytelength $text]
    }
}

proc ::xmpp::transport::tcp::outXML {token xml} {
    return [outText $token [::xmpp::xml::toText $xml]]
}

proc ::xmpp::transport::tcp::openStream {token server args} {
    return [outText $token \
                    [eval [list ::xmpp::xml::streamHeader $server] $args]]
}

proc ::xmpp::transport::tcp::closeStream {token args} {
    variable $token
    upvar 0 $token state

    set len [outText $token [::xmpp::xml::streamTrailer]]

    # TODO
    if {1} {
        ::flush $state(sock)
    } else {
        fconfigure $state(sock) -blocking 1
        ::flush $state(sock)
        vwait $token\(sock)
    }

    return $len
}

proc ::xmpp::transport::tcp::flush {token} {
    variable $token
    upvar 0 $token state

    ::flush $state(sock)
}

proc ::xmpp::transport::tcp::ip {token} {
    variable $token
    upvar 0 $token state

    return [lindex [fconfigure $state(sock)) -sockname] 0]
}

proc ::xmpp::transport::tcp::close {token} {
    variable $token
    upvar 0 $token state

    catch {
        fileevent $state(sock) readable {}
        ::close $state(sock)
    }

    if {[info exists state(parser)]} {
        ::xmpp::xml::free $state(parser)
    }

    catch {unset state}
    return
}

proc ::xmpp::transport::tcp::reset {token} {
    variable $token
    upvar 0 $token state

    ::xmpp::xml::reset $state(parser)
}

proc ::xmpp::transport::tcp::InText {token} {
    variable $token
    upvar 0 $token state

    set msg ""
    catch {set msg [read $state(sock)]}

    ::xmpp::xml::parser $state(parser) parse $msg

    if {[eof $state(sock)]} {
        InEmpty $state(eofCmd)
    }
}

proc ::xmpp::transport::tcp::InXML {cmd xml} {
    after idle $cmd [list $xml]
}

proc ::xmpp::transport::tcp::InEmpty {cmd} {
    after idle $cmd
}

# vim:ts=8:sw=4:sts=4:et
