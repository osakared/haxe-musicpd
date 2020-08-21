package mpd;

typedef ListResult = {
    var type:String;
    var name:String;
}

class ListResultGroup
{
    public var groupType:Null<String> = null;
    public var groupName:Null<String> = null;
    public var results = new Array<ListResult>();

    public function new()
    {
    }
}
