# transport.tcl --
#
#       This file is part of the XMPP library. It implements the XMPP
#       transports infrastructure.
#
# Copyright (c) 2008-2013 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require msgcat

package provide xmpp::transport 0.2

namespace eval ::xmpp::transport {
    namespace export list register unregister use switch

    # A list of registered XMPP transports (tcp, tls etc.)
    variable TransportsList {}
}

# ::xmpp::transport::list --
#
#       Return list of registered XMPP transports.
#
# Arguments:
#       None.
#
# Result:
#       A list of names of already registered transports.
#
# Side effects:
#       None.

proc ::xmpp::transport::list {} {
    variable TransportsList
    return $TransportsList
}

# ::xmpp::transport::register --
#
#       Register new XMPP transport.
#
# Arguments:
#       transport                   Transport name.
#       -opencommand         cmd0   Command to call when opening connection
#                                   (e.g. TCP socket).
#       -abortcommand        cmd1   Command to call when aborting connection if
#                                   opening is asynchronous.
#       -closecommand        cmd2   Command to call when closing an opened
#                                   connection.
#       -resetcommand        cmd3   Command to call when resetting an opened
#                                   connection (usually it resets XML parser).
#       -flushcommand        cmd4   Command to flush buffer (if any) to a
#                                   connection.
#       -outxmlcommand       cmd5   Command which converts XML (e.g. returned
#                                   by ::xmpp::xml::create) to text and sends
#                                   it to a connection.
#       -outtextcommand      cmd6   Command which sends raw text to a
#                                   connection.
#       -openstreamcommand   cmd7   Command which opens XMPP stream over a
#                                   connection.
#       -reopenstreamcommand cmd8   Command which reopens XMPP stream over a
#                                   connection.
#       -closestreamcommand  cmd9   Command which closes XMPP stream over a
#                                   connection.
#       -importcommand       icmd   (optional) Import command
#
# Result:
#       Transport name in case of success or error if the specified transport
#       is already registered or some command argument is missing.
#
# Side effects:
#       Transport is registered.

proc ::xmpp::transport::register {transport args} {
    variable TransportsList
    variable Transports

    if {[lsearch -exact $TransportsList $transport] >= 0} {
        return -code error [::msgcat::mc "Transport \"%s\" already\
                                          registered" $transport]
    }

    foreach {key val} $args {
        ::switch -- $key {
            -opencommand         -
            -abortcommand        -
            -closecommand        -
            -resetcommand        -
            -flushcommand        -
            -ipcommand           -
            -outxmlcommand       -
            -outtextcommand      -
            -openstreamcommand   -
            -reopenstreamcommand -
            -closestreamcommand  -
            -importcommand {
                set attrs($key) $val
            }
            default {
                return -code error [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    set Transports($transport) {}
    foreach key {-opencommand
                 -abortcommand
                 -closecommand
                 -resetcommand
                 -flushcommand
                 -ipcommand
                 -outxmlcommand
                 -outtextcommand
                 -openstreamcommand
                 -reopenstreamcommand
                 -closestreamcommand} {
        if {![info exists attrs($key)]} {
            unset Transports($transport)
            return -code error [::msgcat::mc "Missing option \"%s\"" $key]
        } else {
            lappend Transports($transport) $key $attrs($key)
        }
    }

    foreach key {-importcommand} {
        if {[info exists attrs($key)]} {
            lappend Transports($transport) $key $attrs($key)
        }
    }

    lappend TransportsList $transport
    return $transport
}

# ::xmpp::transport::unregister --
#
#       Remove transport from registered transport list.
#
# Arguments:
#       transport           XMPP Transport name.
#
# Result:
#       Transport name in case of success or error if the transport isn't
#       registered.
#
# Side effects:
#       Transport is unregistered and cannot be used anymore.

proc ::xmpp::transport::unregister {transport} {
    variable TransportsList
    variable Transports

    if {[set idx [lsearch -exact $TransportsList $transport]] < 0} {
        return -code error [::msgcat::mc "Unknown transport \"%s\"" $transport]
    } else {
        set TransportsList [lreplace $TransportsList $idx $idx]
        unset $Transports($transport)
    }

    return $transport
}

proc ::xmpp::transport::open {transport args} {
    variable TransportsList
    variable Transports

    if {[lsearch -exact $TransportsList $transport] < 0} {
        return -code error [::msgcat::mc "Unknown transport \"%s\"" $transport]
    }

    array set attrs $Transports($transport)

    return [uplevel #0 $attrs(-opencommand) $args]
}

# ::xmpp::transport::use --
#
#       Use transport for transferring XMPP data (call a registered command).
#
# Arguments:
#       token               XMPP transport token.
#       command             One of open, abort, close, flush, outXML,
#                           outText, openStream, reopenStream closeStream
#                           (corresponding to ::xmpp::transport::register
#                           options).
#       args                Arguments depending on command.
#
# Result:
#       The result of corresponding called command or error if the specified
#       transport isn't registered or command doesn't belong to the commands
#       list.
#
# Side effects:
#       The side effects of corresponding called command.

proc ::xmpp::transport::use {token command args} {
    variable TransportsList
    variable Transports
    variable $token
    upvar 0 $token state
    set transport $state(transport)

    if {[lsearch -exact $TransportsList $transport] < 0} {
        return -code error [::msgcat::mc "Unknown transport \"%s\"" $transport]
    }

    ::switch -- $command {
        abort        {set key -abortcommand}
        close        {set key -closecommand}
        reset        {set key -resetcommand}
        flush        {set key -flushcommand}
        ip           {set key -ipcommand}
        outXML       {set key -outxmlcommand}
        outText      {set key -outtextcommand}
        openStream   {set key -openstreamcommand}
        reopenStream {set key -reopenstreamcommand}
        closeStream  {set key -closestreamcommand}
        default {
            return -code error [::msgcat::mc "Illegal command \"%s\"" $command]
        }
    }

    array set attrs $Transports($transport)

    return [uplevel #0 $attrs($key) $token $args]
}

# ::xmpp::transport::switch --
#
#       Switch XMPP transport.
#
# Arguments:
#       token               XMPP transport token.
#       transport           XMPP transport name to switch.
#       args                Arguments for import procedure. See also
#                           ::xmpp::tls::import and ::xmpp::zlib::import.
#
# Result:
#       A new XMPP token to use.
#
# Side effects:
#       Transport for XMPP connection is changed.

proc ::xmpp::transport::switch {token transport args} {
    variable TransportsList
    variable Transports

    if {[lsearch -exact $TransportsList $transport] < 0} {
        return -code error [::msgcat::mc "Unknown transport \"%s\"" $transport]
    }

    array set attrs $Transports($transport)

    if {[catch {
            uplevel #0 $attrs(-importcommand) [::list $token] $args
        } token2]} {

        return -code error \
               [::msgcat::mc "Can't switch transport to \"%s\": %s" \
                             $transport $token2]
    } else {
        return $token2
    }
}

# vim:ts=8:sw=4:sts=4:et
