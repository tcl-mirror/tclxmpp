#!/usr/bin/env tclsh

# chessbot.tcl --
#
#       This file is an example provided with the XMPP library. It implements
#       a simple XMPP bot which uses GNU Chess engine and Tkabber Chess plugin
#       protocol to play chess.
#
# Copyright (c) 2008 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require xmpp::full

# Register games:board XMLNS
::xmpp::iq::register set * games:board ProcessGamesBoard

# ExecChessEngine --
#
#       Start GNU Chess process and setup the opened pipe.
#
# Arguments:
#       xlib        XMPP library token.
#       jid         Opponent's JID.
#       gid         Game ID.
#
# Result:
#       A pipe to communicate with GNU Chess process.
#
# Side effects:
#       A new GNU Chess process is created.
#
# Bugs:
#       Since there's a possibility to close game window which will never
#       be noticed by the bot (and gnuchess will never be killed) the process
#       is started with option --easy and at least doesn't consume much
#       processor power. A proper solution would be to monitor game
#       periodically (though the protocol doesn't give such an option).

proc ExecChessEngine {xlib jid gid} {
    set fd [open "|gnuchess --xboard --easy" r+]
    fconfigure $fd -blocking 0 -buffering line
    fileevent $fd readable [list ReadFromChessEngine $xlib $jid $gid $fd]
    return $fd
}

# WriteToChessEngine --
#
#       Send a command to a running chess process.
#
# Arguments:
#       jid         Opponent's JID.
#       gid         Game ID.
#       text        Text to send.
#
# Result:
#       Empty string.
#
# Side effects:
#       A chess process gets the specified string (and will reply later).

proc WriteToChessEngine {jid gid text} {
    global games

    puts "WriteToChessEngine $jid $gid $text"
    puts $games([list $jid $gid]) $text
    return
}

# ReadFromChessEngine --
#
#       Read a string from a running chess process, and process it.
#
# Arguments:
#       xlib        XMPP library token.
#       jid         Opponent's JID.
#       gid         Game ID.
#       fd          Pipe to communicate with GNU Chess process.
#
# Result:
#       Empty string.
#
# Side effects:
#       If EOF is got (chess process is finished) then the corresponding
#       game is finished. If a move is got then it's sent to the opponent.
#       If the game is finished with some defined result then quit message
#       is sent to the engine.

proc ReadFromChessEngine {xlib jid gid fd} {
    global games

    gets $fd text
    puts "ReadFromChessEngine $jid $gid $text"

    if {[eof $fd]} {
        close $fd
        catch {unset games([list $jid $gid])}
    }

    if {[regexp {^My move is: (\S+)} $text -> move]} {
        SendTurnIQ $xlib $jid $gid [Move $move]
    } elseif {[regexp {^offer draw} $text]} {
        SendTurnIQ $xlib $jid $gid [::xmpp::xml::create accept]
    } elseif {[regexp {^resign} $text]} {
        SendTurnIQ $xlib $jid $gid [::xmpp::xml::create resign]
    } elseif {[regexp {^(1-0|0-1|1/2-1/2) \{.*\}} $text]} {
        WriteToChessEngine $jid $gid quit
    }
    return
}

# Move --
#
#       Map GNU Chess move g2g1q to
#       <move pos="6,1;6,0"><promotion>queen</promotion></move>.
#
# Arguments:
#       move        GNU Chess move.
#
# Result:
#       Tkabber chess protocol move XML element.
#
# Side effects:
#       None.

proc Move {move} {
    set map {a 0 b 1 c 2 d 3 e 4 f 5 g 6 h 7}

    set mlist [split $move ""]
    set cf [string map $map [lindex $mlist 0]]
    set rf [lindex $mlist 1]
    incr rf -1
    set ct [string map $map [lindex $mlist 2]]
    set rt [lindex $mlist 3]
    incr rt -1

    switch -- [lindex $mlist 4] {
        q {set subels [list [::xmpp::xml::create promotion -cdata queen]]}
        r {set subels [list [::xmpp::xml::create promotion -cdata rook]]}
        b {set subels [list [::xmpp::xml::create promotion -cdata bishop]]}
        n {set subels [list [::xmpp::xml::create promotion -cdata knight]]}
        default {set subels {}}
    }

    set pos $cf,$rf\;$ct,$rt

    return [::xmpp::xml::create move -attrs [list pos $pos] \
                                     -subelements $subels]
}

# SendTurnIQ --
#
#       Send chess turn query to an opponent.
#
# Arguments:
#       xlib        XMPP library token.
#       jid         Opponent's JID.
#       gid         Game ID.
#       xmlElement  Turn subelement (move, resign etc.)
#
# Result:
#       Empty string.
#
# Side effects.
#       A query is sent.

proc SendTurnIQ {xlib jid gid xmlElement}  {
    ::xmpp::sendIQ $xlib set \
            -query [::xmpp::xml::create turn \
                            -xmlns games:board \
                            -attrs [list type chess id $gid] \
                            -subelement $xmlElement] \
            -to $jid \
            -command [list CheckTurnResult $jid $gid]
    return
}

# CheckTurnResult --
#
#       Check the answer on chess turn query.
#
# Arguments:
#       jid         Opponent's JID.
#       gid         Game ID.
#       status      Query status (ok or error).
#       xml         Either error stanza (if status is error) or result stanza.
#
# Result:
#       Empty string.
#
# Side effects:
#       If status isn't ok then game $gid with opponent $jid is finished.

proc CheckTurnResult {jid gid status xml} {
    if {![string equal $status ok]} {
        WriteToChessEngine $jid $gid quit
    }
    return
}

# Turn --
#
#       Parse received turn XML element and send it to GNU Chess process.
#
# Arguments:
#       jid         Opponent's JID.
#       gid         Game ID.
#       xmlElements  Turn subelements (move, resign etc.).
#
# Result:
#       Either tuple {error, ...} or tuple {result, ...}.
#
# Side effects:
#       A move is passed to GNU Chess engine in case of successful parsing.
#
# Bugs:
#       A success is returned regardless if the move is legal or not. This
#       means that illegal move will break game process (GNU Chess will not
#       accept it, but the opponent will not receive error).

proc Turn {jid gid xmlElements} {
    global games

    set map {0 a 1 b 2 c 3 d 4 e 5 f 6 g 7 h}

    set move 0
    set draw 0
    foreach element $xmlElements {
        ::xmpp::xml::split $element tag xmlns attrs cdata subels
        switch -- $tag {
            move {
                set pos [::xmpp::xml::getAttr $attrs pos]
                set poss [split $pos ";"]
                if {[llength $poss] == 2} {
                    set pos1 [split [lindex $poss 0] ,]
                    set pos2 [split [lindex $poss 1] ,]
                    if {[llength $pos1] == 2 && [llength $pos2] == 2} {
                        set cf [string map $map [lindex $pos1 0]]
                        set rf [lindex $pos1 1]
                        incr rf
                        set ct [string map $map [lindex $pos2 0]]
                        set rt [lindex $pos2 1]
                        incr rt
                        set prom ""
                        foreach selement $subels {
                            ::xmpp::xml::split $selement stag sxmlns sattrs \
                                                         scdata ssubels
                            if {[string equal $stag promotion]} {
                                switch -- $scdata {
                                    queen  {set prom q}
                                    rook   {set prom r}
                                    bishop {set prom b}
                                    knight {set prom n}
                                }
                            }
                        }
                        set move 1
                    }
                }
            }
            resign {
                WriteToChessEngine $jid $gid quit
                return [list result [::xmpp::xml::create turn \
                                             -xmlns games::board \
                                             -attrs [list type chess \
                                                          id $gid]]]
            }
            accept {
                # TODO
                if {0} {
                    WriteToChessEngine $jid $gid quit
                    return [list result [::xmpp::xml::create turn \
                                                 -xmlns games::board \
                                                 -attrs [list type chess \
                                                              id $gid]]]
                } else {
                    return {error modify not-acceptable}
                }
            }
            draw {
                set draw 1
            }
        }
    }

    if {$move} {
        WriteToChessEngine $jid $gid $cf$rf$ct$rt$prom
        if {$draw} {
            WriteToChessEngine $jid $gid draw
        }
        return [list result [::xmpp::xml::create turn \
                                     -xmlns games:board \
                                     -attrs [list type chess id $gid]]]
    } else {
        return {error modify not-acceptable}
    }
}

# CreateGame --
#
#       Create new chess game.
#
# Arguments:
#       xlib        XMPP library token.
#       jid         Opponent's JID.
#       gid         Game ID.
#       color       Opponents figures color (white or black).
#
# Result:
#       XML stanza to return to opponent.
#
# Side effects:
#       A new GNU Chess process is started (its pipe is stored in a global
#       variable) and if color is black then the engine is asked to make turn
#       first.

proc CreateGame {xlib jid gid color} {
    global games

    set games([list $jid $gid]) [ExecChessEngine $xlib $jid $gid]

    if {[string equal $color black]} {
        WriteToChessEngine $jid $gid go
    }

    return [list result \
                 [::xmpp::xml::create create \
                          -xmlns games:board \
                          -attrs [list type chess id $gid]]]
}

# Exists --
#
#       Check if the game exists.
#
# Arguments:
#       jid         Opponent's JID.
#       gid         Game ID.
#
# Result:
#       1 if a variable with corresponding pipe exists, 0 otherwise.
#
# Side effects:
#       None.

proc Exists {jid gid} {
    global games

    return [info exists games([list $jid $gid])]
}

# ProcessGamesBoard --
#
#       Parse query with XMLNS games:board and return result or error.
#
# Arguments:
#       xlib        XMPP library token.
#       from        From JID.
#       xmlElement  Query stanza.
#
# Result:
#       Either tuple {error, ...} or tuple {result, ...}.
#
# Side effects:
#       If a query is correct then the corresponding procedure is called.

proc ProcessGamesBoard {xlib from xmlElement args} {
    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels

    set game [::xmpp::xml::getAttr $attrs type]
    if {![string equal $game chess]} {
        return {error cancel service-not-available}
    }

    if {[::xmpp::xml::isAttr $attrs id]} {
        set gid [::xmpp::xml::getAttr $attrs id]
    } else {
        return {error modify bad-request}
    }

    switch -- $tag {
        create {
            if {[::xmpp::xml::isAttr $attrs color]} {
                set color [::xmpp::xml::getAttr $attrs color]
                switch -- $color {
                    white -
                    black {}
                    default {
                        return {error modify bad-request}
                    }
                }
            } else {
                set color white
            }
            if {[Exists $from $gid]} {
                return {error modify bad-request}
            } else {
                return [CreateGame $xlib $from $gid $color]
            }
        }
        turn {
            if {[Exists $from $gid]} {
                return [Turn $from $gid $subels]
            } else {
                return {error cancel item-not-found}
            }
        }
    }

    return {error modify bad-request}
}


array set options [list -host     "" \
                        -port     5222 \
                        -server   localhost \
                        -username user \
                        -resource "GNU Chess"
                        -password secret \
                        -compress false \
                        -tls      false \
                        -starttls true \
                        -sasl     true \
                        -poll     false \
                        -url      ""]

if {[catch {
    if {([file exists [set file .chessbotrc.tcl]]) \
            || ([file exists [set file ~/.chessbotrc.tcl]])} {
        set args {}

        source $file

        array set at [list -permissions 600]
        array set at [file attributes $file]

        if {([set x [lsearch -exact $args "-password"]] > 0) \
                    && (![expr $x%2]) \
                    && (![string match *00 $at(-permissions)])} {
            error "file should be mode 0600"
        }

        if {[llength $args] > 0} {
            array set options $args
        }
    }
} result]} {
    puts stderr "error in $file: $result"
}

array set options $argv

if {[string equal $options(-host) ""]} {
    set options(-host) $options(-server)
}

# Create an XMPP library instance
set xlib [::xmpp::new]

# Connect to a server
if {$options(-poll)} {
    # HTTP-polling

    ::xmpp::connect $xlib -transport poll \
                          -url $options(-url)
} elseif {$options(-tls)} {
    # Legacy SSL

    ::xmpp::connect $xlib -transport tls \
                          -host $options(-host) \
                          -port $options(-port)
} else {
    # TCP channel (with possible upgrade)

    ::xmpp::connect $xlib -host $options(-host) \
                          -port $options(-port)
}

if {$options(-sasl) || \
        (!$options(-tls) && ($options(-starttls) || $options(-compress)))} {
    # STARTTLS and stream compression require SASL authentication

    # Open XMPP stream
    ::xmpp::openStream $xlib $options(-server) -version 1.0

    if {!$options(-tls) && $options(-starttls)} {
        # STARTTLS

        ::xmpp::starttls::starttls $xlib
    } elseif {!$options(-tls) && $options(-compress)} {
        # Compression

        ::xmpp::compress::compress $xlib
    }

    # Authenticate
    ::xmpp::sasl::auth $xlib -username $options(-username) \
                             -password $options(-password) \
                             -resource $options(-resource) \
} else {
    # Non-SASL authentication

    # Open XMPP stream
    set sessionID [::xmpp::openStream $xlib $options(-server)]

    # Authenticate
    ::xmpp::auth::auth $xlib -sessionID $sessionID \
                             -username  $options(-username) \
                             -password  $options(-password) \
                             -resource  $options(-resource)
}

# Send initial presence
::xmpp::sendPresence $xlib -priority -1

# Start event loop
vwait forever

# vim:ts=8:sw=4:sts=4:et
