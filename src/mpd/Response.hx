package mpd;

import haxe.io.Bytes;

typedef NameValuePair = {
    var name:String;
    var value:String;
}

class Response
{
    public var binary:Bytes = null;
    @:isVar public var values(get, null):Array<NameValuePair> = null;

    private function get_values()
    {
        if (values == null) {
            values = new Array<NameValuePair>();
        }
        return values;
    }

    public function new()
    {
    }
}