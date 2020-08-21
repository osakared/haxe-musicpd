package mpd;

/**
 * Represents a single audio output
 */
class AudioOutput
{
    public var id:Int;
    public var name:String;
    public var plugin:String;
    public var outputEnabled:Bool = false;
    public var attributes = new Array<NameValuePair>();

    public function new(_id:Int)
    {
        id = _id;
    }
}