# tcp.tcl --
#
#       This file is part of the XMPP library. It provides support for the
#       XMPP stream over TCP sockets.
#
# Copyright (c) 2008-2010 Sergei Golovan <sgolovan@nes.ru>
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
            -opencommand        [namespace code open]       \
            -abortcommand       [namespace code abort]      \
            -closecommand       [namespace code close]      \
            -resetcommand       [namespace code reset]      \
            -flushcommand       [namespace code flush]      \
            -ipcommand          [namespace code ip]         \
            -outxmlcommand      [namespace code outXML]     \
            -outtextcommand     [namespace code outText]    \
            -openstreamcommand  [namespace code openStream] \
            -closestreamcommand [namespace code closeStream]
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
#       -streamheadercommand  cmd1  Command to call when XMPP stream header
#                                   (<stream:stream>) is received.
#       -streamtrailercommand cmd2  Command to call when XMPP stream trailer
#                                   (</stream:stream>) is received.
#       -stanzacommand        cmd3  Command to call when XMPP stanza is
#                                   received.
#       -eofcommand           cmd4  End-of-file callback.
#       (other arguments are passed to [::pconnect::socket])
#       -domain string              "inet" (default) or "inet6"
#       -proxy string               Proxy type "" (default), "socks4",
#                                   "socks5", or "https"
#       -host string                Proxy hostname (required if -proxy
#                                   isn't empty)
#       -port integer               Proxy port number (required if -proxy
#                                   isn't empty)
#       -username string            Proxy user ID
#       -password string            Proxy password
#       -useragent string           Proxy user agent (for HTTP proxies)
#
# Result:
#       Transport token is returned to allow to abort connection process in
#       asynchronous mode. In synchronous mode token is returned in case of
#       success or error is raised if the connection is failed.
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
            -streamheadercommand  {set state(streamHeaderCmd)  $val}
            -streamtrailercommand {set state(streamTrailerCmd) $val}
            -stanzacommand        {set state(stanzaCmd)        $val}
            -eofcommand           {set state(eofCmd)           $val}
            default               {lappend newArgs $key $val}
        }
    }

    if {![info exists cmd]} {
        # Synchronous mode
        set state(sock) [eval [list ::pconnect::socket $host $port] $newArgs]
        Configure $token
    } else {
        # Asynchronous mode
        if {[catch {
                set state(pconnect) \
                    [eval [list ::pconnect::socket $host $port] $newArgs \
                          [list -command [namespace code [list OpenAux $token \
                                                               $cmd]]]]
            } msg]} {
            # We can't even open a socket

            after idle [namespace code [list OpenAux $token $cmd error $msg]]
        }
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

    catch {unset state(pconnect)}

    if {[string equal $status ok]} {
        set state(sock) $sock
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

# ::xmpp::transport::tcp::abort --
#
#       Abort connection which isn't fully opened yet.
#
# Arguments:
#       token           Transport token.
#
# Result:
#       Empty string.
#
# Side effects:
#       Connection token is destroyed and the connection is aborted.

proc ::xmpp::transport::tcp::abort {token} {
    variable $token
    upvar 0 $token state

    if {[info exists state(pconnect)]} {
        # If ::pconnect::abort returns error then propagate it to the caller
        ::pconnect::abort $state(pconnect)
    }

    if {[info exists state(parser)]} {
        ::xmpp::xml::free $state(parser)
    }

    unset state

    return
}

# ::xmpp::transport::tcp::outText --
#
#       Send text to XMPP server.
#
# Arguments:
#       token           Transport token.
#       text            Text to send.
#
# Result:
#       Bytelength of a sent text.
#
# Side effects:
#       Text is sent to the server.

proc ::xmpp::transport::tcp::outText {token text} {
    variable $token
    upvar 0 $token state

    if {[catch {puts -nonewline $state(sock) $text} err]} {
        return -1
    } else {
        # TODO
        return [string bytelength $text]
    }
}

# ::xmpp::transport::tcp::outXML --
#
#       Send XML element to XMPP server.
#
# Arguments:
#       token           Transport token.
#       xml             XML to send.
#
# Result:
#       Bytelength of a textual representation of a sent XML.
#
# Side effects:
#       Text is sent to the server.

proc ::xmpp::transport::tcp::outXML {token xml} {
    return [outText $token [::xmpp::xml::toText $xml]]
}

# ::xmpp::transport::tcp::openStream --
#
#       Send XMPP stream header to XMPP server.
#
# Arguments:
#       token           Transport token.
#       server          XMPP server.
#       args            Arguments for [::xmpp::xml::streamHeader].
#
# Result:
#       Bytelength of a textual representation of a sent header.
#
# Side effects:
#       Text is sent to the server.

proc ::xmpp::transport::tcp::openStream {token server args} {
    return [outText $token \
                    [eval [list ::xmpp::xml::streamHeader $server] $args]]
}

# ::xmpp::transport::tcp::closeStream --
#
#       Send XMPP stream trailer to XMPP server and start disconnecting
#       procedure.
#
# Arguments:
#       token           Transport token.
#
# Result:
#       Bytelength of a textual representation of a sent header.
#
# Side effects:
#       Text is sent to the server.

proc ::xmpp::transport::tcp::closeStream {token} {
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

# ::xmpp::transport::tcp::flush --
#
#       Flush XMPP channel.
#
# Arguments:
#       token           Transport token.
#
# Result:
#       Empty string.
#
# Side effects:
#       Pending data is sent to the server.

proc ::xmpp::transport::tcp::flush {token} {
    variable $token
    upvar 0 $token state

    ::flush $state(sock)
    return
}

# ::xmpp::transport::tcp::ip --
#
#       Return IP of an outgoing socket.
#
# Arguments:
#       token           Transport token.
#
# Result:
#       IP address.
#
# Side effects:
#       None.

proc ::xmpp::transport::tcp::ip {token} {
    variable $token
    upvar 0 $token state

    return [lindex [fconfigure $state(sock) -sockname] 0]
}

# ::xmpp::transport::tcp::close --
#
#       Close XMPP channel.
#
# Arguments:
#       token           Transport token.
#
# Result:
#       Empty string.
#
# Side effects:
#       Transport token and XML parser are destroyed.

proc ::xmpp::transport::tcp::close {token} {
    variable $token
    upvar 0 $token state

    catch {fileevent $state(sock) readable {}}
    catch {::close $state(sock)}

    if {[info exists state(parser)]} {
        ::xmpp::xml::free $state(parser)
    }

    catch {unset state}
    return
}

# ::xmpp::transport::tcp::reset --
#
#       Reset XMPP stream.
#
# Arguments:
#       token           Transport token.
#
# Result:
#       Empty string.
#
# Side effects:
#       XML parser is reset.

proc ::xmpp::transport::tcp::reset {token} {
    variable $token
    upvar 0 $token state

    ::xmpp::xml::reset $state(parser)
    return
}

# ::xmpp::transport::tcp::InText --
#
#       A helper procedure which is called when a new portion of data is
#       received from XMPP server. It receives the data from a socket and
#       feeds XML parser with them.
#
# Arguments:
#       token           Transport token.
#
# Result:
#       Empty string.
#
# Side effects:
#       The text is parsed and if it completes top-level stanza then an
#       appropriate callback is invoked.

proc ::xmpp::transport::tcp::InText {token} {
    variable $token
    upvar 0 $token state

    if {[catch {read $state(sock)} msg]} {
        fileevent $state(sock) readable {}
        ::close $state(sock)
        InEmpty $state(eofCmd)
        return
    }

    ::xmpp::xml::parser $state(parser) parse $msg

    if {[eof $state(sock)]} {
        fileevent $state(sock) readable {}
        ::close $state(sock)
        InEmpty $state(eofCmd)
    }
}

# ::xmpp::transport::tcp::InXML --
#
#       A helper procedure which is called when a new XML stanza is parsed.
#       It then calls a specified command as an idle callback.
#
# Arguments:
#       cmd             Command to call.
#       xml             Stanza to pass to the command.
#
# Result:
#       Empty string.
#
# Side effects:
#       After entering event loop the spaecified command is called.

proc ::xmpp::transport::tcp::InXML {cmd xml} {
    after idle $cmd [list $xml]
}

# ::xmpp::transport::tcp::InEmpty --
#
#       A helper procedure which is called when XMPP stream is finished.
#       It then calls a specified command as an idle callback.
#
# Arguments:
#       cmd             Command to call.
#
# Result:
#       Empty string.
#
# Side effects:
#       After entering event loop the spaecified command is called.

proc ::xmpp::transport::tcp::InEmpty {cmd} {
    after idle $cmd
}

# vim:ts=8:sw=4:sts=4:et
