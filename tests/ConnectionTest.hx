package;

import mpd.MusicPD;
import tink.unit.Assert.*;

@:asserts
class ConnectionTest
{
    public function new()
    {
    }

    public function testConnection()
    {
        MusicPD.connect('192.168.1.166').handle(function(outcome) {
            switch outcome {
                case Success(musicPD):
                    musicPD.getReplayGainStatus();
                case Failure(error):
                    trace(error);
            }
        });
        return assert(true);
    }
}