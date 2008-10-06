# transport.tcl --
#
#       This file is part of the XMPP library. It implements the XMPP
#       transports infrastructure.
#
# Copyright (c) 2008 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require msgcat

package provide xmpp::transport 0.1

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
#       -openCommand        cmd0    Command to call when opening connection
#                                   (e.g. TCP socket).
#       -abortCommand       cmd1    Command to call when aborting connection if
#                                   opening is asynchronous.
#       -closeCommand       cmd2    Command to call when closing an opened
#                                   connection.
#       -resetCommand       cmd3    Command to call when resetting an opened
#                                   connection (usually it resets XML parser).
#       -flushCommand       cmd4    Command to flush buffer (if any) to a
#                                   connection.
#       -outXMLCommand      cmd5    Command which converts XML (e.g. returned
#                                   by ::xmpp::xml::create) to text and sends
#                                   it to a connection.
#       -outTextCommand     cmd6    Command which sends raw text to a
#                                   connection.
#       -openStreamCommand  cmd7    Command which opens XMPP stream over a
#                                   connection.
#       -closeStreamCommand cmd8    Command which closes XMPP stream over a
#                                   connection.
#       -importCommand      icmd    (optional) Import command
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
        return -code error \
               -errorinfo [::msgcat::mc "Transport \"%s\" already\
                                         registered" $transport]
    }

    foreach {key val} $args {
        ::switch -- $key {
            -openCommand        -
            -abortCommand       -
            -closeCommand       -
            -resetCommand       -
            -flushCommand       -
            -outXMLCommand      -
            -outTextCommand     -
            -openStreamCommand  -
            -closeStreamCommand -
            -importCommand {
                set attrs($key) $val
            }
            default {
                return -code error \
                       -errorinfo [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    set Transports($transport) {}
    foreach key {-openCommand
                 -abortCommand
                 -closeCommand
                 -resetCommand
                 -flushCommand
                 -outXMLCommand
                 -outTextCommand
                 -openStreamCommand
                 -closeStreamCommand} {
        if {![info exists attrs($key)]} {
            unset Transports($transport)
            return -code error \
                   -errorinfo [::msgcat::mc "Missing option \"%s\"" $key]
        } else {
            lappend Transports($transport) $key $attrs($key)
        }
    }

    foreach key {-importCommand} {
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
        return -code error \
               -errorinfo [::msgcat::mc "Unknown transport \"%s\"" $transport]
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
        return -code error \
               -errorinfo [::msgcat::mc "Unknown transport \"%s\"" $transport]
    }

    array set attrs $Transports($transport)

    return [uplevel #0 $attrs(-openCommand) $args]
}

# ::xmpp::transport::use --
#
#       Use transport for transferring XMPP data (call a registered command).
#
# Arguments:
#       token               XMPP transport name.
#       command             One of open, abort, close, flush, outXML,
#                           outText, openStream, closeStream (corresponding
#                           to ::xmpp::transport::register options).
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
        return -code error \
               -errorinfo [::msgcat::mc "Unknown transport \"%s\"" $transport]
    }

    ::switch -- $command {
        abort       {set key -abortCommand}
        close       {set key -closeCommand}
        reset       {set key -resetCommand}
        flush       {set key -flushCommand}
        outXML      {set key -outXMLCommand}
        outText     {set key -outTextCommand}
        openStream  {set key -openStreamCommand}
        closeStream {set key -closeStreamCommand}
        default {
            return -code error \
                   -errorinfo [::msgcat::mc "Illegal command \"%s\"" $command]
        }
    }

    array set attrs $Transports($transport)

    return [uplevel #0 $attrs($key) $token $args]
}

proc ::xmpp::transport::switch {token transport args} {
    variable TransportsList
    variable Transports

    if {[lsearch -exact $TransportsList $transport] < 0} {
        return -code error \
               -errorinfo [::msgcat::mc "Unknown transport \"%s\"" $transport]
    }

    array set attrs $Transports($transport)

    if {[catch {
            uplevel #0 $attrs(-importCommand) [::list $token] $args
        } token2]} {

        return -code error \
               -errorinfo [::msgcat::mc "Can't switch transport to \"%s\": %s" \
                                        $transport $token2]
    } else {
        return $token2
    }
}

# vim:ts=8:sw=4:sts=4:et
