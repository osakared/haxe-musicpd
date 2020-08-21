package mpd;

/**
 * Represents a channel and all the messages received on said channel
 */
class ChannelMessages
{
    public var channel:String;
    public var messages = new Array<String>();

    public function new(_channel:String)
    {
        channel = _channel;
    }
}