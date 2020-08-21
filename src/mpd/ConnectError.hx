package mpd;

/**
 * Error received when attempting to connect to mpd
 */
enum ConnectError
{
    InvalidResponseString(response:String);
}