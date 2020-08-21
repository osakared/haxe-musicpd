package mpd;

/**
 * Useful template class for responses from mpd that contain multiple pieces of data
 */
class CollectionResponse<T>
{
    public var collection = new Array<T>();
    public var response:Null<Response> = null;

    public function new()
    {
    }
}