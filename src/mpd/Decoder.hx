package mpd;

class Decoder
{
    public var plugin:String;
    public var suffixes = new Array<String>();
    public var mimeTypes = new Array<String>();

    public function new(_plugin:String)
    {
        plugin = _plugin;
    }
}
