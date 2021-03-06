###############################################################################
#
#  easy-signaling - A WebRTC signaling server
#  Copyright (C) 2014  Stephan Thamm
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU Affero General Public License as
#  published by the Free Software Foundation, either version 3 of the
#  License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU Affero General Public License for more details.
#
#  You should have received a copy of the GNU Affero General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################################################

###*
# Concept of a channel connecting the client to the signaling server. This is not an actual class but the description of the interface used to represent the communication channels. For a reference implementation look at `WebsocketChannel`.
#
# The interface expects JavaScript Objects to come in and out of the API. You most propably want to encode the messages on the transport channel, for example using JSON.
#
# @class Channel
# @extends events.EventEmitter
###
###*
# A message was received. You might have to decode the data.
# @event message
# @param {Object} data The decoded message
###
###*
# The connection was closed
# @event closed
###
###*
# An error occured with the underlying connection.
# @event error
# @param {Error} error The error which occured
###
###*
# Send data to the client. You might have to encode the data for transmission.
# @method send
# @param {Object} data The message to be sent
###
###*
# Close the connection to the client
# @method close
###

uuid = require('node-uuid')

EventEmitter = require('events').EventEmitter

is_empty = (obj) ->
  for _, _ of obj
    return false

  return true

###*
# A simple signaling server for WebRTC applications
# @module easy-signaling
###

###*
# Manages `Room`s and its `Guest`s
# @class Hotel
# @extends events.EventEmitter
#
# @constructor
#
# @example
#     var hotel = new Hotel()
#     guest_a = hotel.create_guest(conn_a, 'room')
#     guest_b = hotel.create_guest(conn_b, 'room')
###
class Hotel extends EventEmitter

  ###*
  # A new room was created
  # @event room_created
  # @param {Room} room The new room
  ###

  ###*
  # A new room was removed because all guests left
  # @event room_removed
  # @param {Room} room The empty room
  ###

  ###*
  # An object containing the rooms with their names as keys
  # @property rooms
  # @private
  ###

  constructor: () ->
    @rooms = {}


  ###*
  # Get a room. The room is created if it did not exist. The room will be removed when it throws `empty`.
  # @method get_room
  # @private
  # @param {String} name The name of the room
  # @return {Room}
  ###
  get_room: (name) ->
    if @rooms[name]?
      return @rooms[name]

    room = @rooms[name] = new Room(name, this)

    room.on 'empty', () =>
      delete @rooms[name]
      @emit('room_removed', room)

    @emit('room_created', room)

    return room


  ###*
  # Create a new guest which might join the room with the given name
  # @method create_guest
  # @param {Channel} conn The connection to the guest
  # @param {String} room_name The name of the room to join
  # @return {Guest}
  ###
  create_guest: (conn, room_name) ->
    return new Guest(conn, () => @get_room(room_name))


###*
# A room containing and conencting `Guest`s. Can be created by a `Hotel` or used alone.
# @class Room
# @extends events.EventEmitter
#
# @constructor
# @param {String} name
#
# @example
#     var room = new Room()
#     guest_a = room.create_guest(conn_a)
#     guest_b = room.create_guest(conn_b)
###
class Room extends EventEmitter

  ###*
  # A guest joined the room
  # @event guest_joined
  # @param {Guest} guest The new guest
  ###

  ###*
  # A guest left the room
  # @event guest_left
  # @param {Guest} guest The leaving guest
  ###

  ###*
  # The room was left by all guests
  # @event empty
  ###

  ###*
  # The name of the room
  # @property name
  # @readonly
  ###

  ###*
  # The current guests of the room
  # @property guests
  # @readonly
  # @private
  ###

  constructor: (@name) ->
    @guests = {}


  ###*
  # Send a message to all guest except the sender
  # @method broadcast
  # @private
  # @param {Object} msg The message
  # @param {String} sender The id of the sender of the message (who will be skipped)
  ###
  broadcast: (msg, sender) ->
    for id, guest of @guests
      if guest.id != sender
        guest.send(msg)


  ###*
  # Send a message to a guest
  # @method send
  # @private
  # @param {Object} msg The message
  # @param {String} recipient The recipient of the message
  # @return {Boolean} True if the recipient exists
  ###
  send: (msg, recipient) ->
    if @guests[recipient]
      @guests[recipient].send(msg)
      return true
    else
      return false


  ###*
  # A guest joins the room. Will be removed when it emits 'left'
  # @method join
  # @private
  # @param {Guest} guets The guest which joins the room
  # @return {Boolean} `true` if and only if the guest could join
  ###
  join: (guest) ->
    if @guests[guest.id]?
      return false

    @guests[guest.id] = guest

    @emit('guest_joined', guest)

    guest.on 'left', () =>
      if not @guests[guest.id]?
        return

      delete @guests[guest.id]

      @emit('guest_left', guest)

      if is_empty(@guests)
        @emit('empty')

    return true


  ###*
  # Create a guest which might join the room
  # @method create_guest
  # @param {Channel} conn The connection to the guest
  # @return {Guest}
  ###
  create_guest: (conn) ->
    return new Guest(conn, () => @)


###*
# A guest which might join a `Room`.
#
# It will join the room once the client sends 'join' and and leave once it emits the 'left' event.
#
# @class Guest
# @extends events.EventEmitter
#
# @constructor
# @param {Channel} conn The connection to the guest
# @param {Function} room_fun Function which will be called upon joining and which should return the Room to join
###
class Guest extends EventEmitter

  ###*
  # Guest joined a room
  # @event joined
  # @param {Room} room The joined room
  ###

  ###*
  # Guest left the room
  # @event left
  # @param {Room} room The joined room
  ###

  ###*
  # The status of the guest changed
  # @event status_changed
  # @param {Object} status The new status
  ###

  ###*
  # The unique identifier of the guest
  # @property id
  # @readonly
  # @type String
  ###

  ###*
  # The status object of the guest. Will only be available after joining.
  # @property status
  # @readonly
  # @type Object
  ###

  constructor: (@conn, @room_fun) ->
    @conn.on 'message', (data) => @receive(data)
    @conn.on 'error', (msg) => @error(msg)
    @conn.on 'closed', () => @closing()


  ###*
  # The guest receives data
  # @method receive
  # @private
  # @param {Object} data The incoming message
  ###
  receive: (data) ->
    if not data.type?
      @error("Incoming message does not have a type")
      return

    switch data.type
      when 'join'
        # get/create room

        @room = @room_fun()

        # get unique id

        while not @id? or @room.guests[@id]?
          @id = uuid.v4()

        # prepare peer list

        peers = {}

        for id, guest of @room.guests
          peers[id] = guest.status

        # try to join

        if not @room.join(@)
          @error("Unable to join")
          return

        # save status

        @status = data.status or {}

        # tell new guest

        @send({
          type: 'joined'
          id: @id
          peers: peers
        })

        # tell everyone else

        @room.broadcast({
          type: 'peer_joined'
          peer: @id
          status: @status
        }, @id)

        # tell library user

        @emit('joined', @room)
        @emit('status_changed', @status)

      when 'to'
        if not data.peer? or not data.event?
          @error("'to' is missing a mandatory value")
          return

        if not @room?
          @error("Attempted 'to' without being in a room")
          return

        # pass on
        if not @room.send({type: 'from', peer: @id, event: data.event, data: data.data}, data.peer)
          @error("Trying to send to unknown peer")

      when 'status'
        if not data.status?
          @error("'update_status' is missing the status")
          return

        if not @room?
          @error("Attempted 'status' without being in a room")
          return

        @status = data.status
        @emit('status_changed', @status)

        @room.broadcast({type: 'peer_status', peer: @id, status: data.status}, @id)

      when 'leave'
        @conn.close()


  ###*
  # The guest sends data
  # @method send
  # @private
  # @param {Object} data The outgoing message
  ###
  send: (data) ->
    @conn.send(data)


  ###*
  # The guest encountered an error
  # @method error
  # @private
  # @param {Error} The error which was encountered
  ###
  error: (msg) ->
    # tell client
    @send {
      type: 'error'
      msg: msg
    }

    # tell library user
    #@emit('error', msg)


  ###*
  # The connection to the guest is closing
  # @method closing
  # @private
  ###
  closing: () ->
    @room?.broadcast {
      type: 'peer_left'
      peer: @id
    }, @id

    @emit('left')


module.exports =
  Hotel: Hotel
  Room: Room
  Guest: Guest

