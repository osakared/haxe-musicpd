package mpd;

/**
 * Replay gain mode
 */
enum abstract ReplayGainMode(String)
{
    var ReplayGainOff = 'off';
    var ReplayGainTrack = 'track';
    var ReplayGainAlbum = 'album';
    var ReplayGainAuto = 'auto';
    var Unknown = 'unknown';

    @:from
    static public function fromString(s:String)
    {
        return switch s.toLowerCase() {
            case 'off': ReplayGainOff;
            case 'track': ReplayGainTrack;
            case 'album': ReplayGainAlbum;
            case 'auto': ReplayGainAuto;
            default: trace('unrecognized tag $s'); Unknown;
        }
    }
}