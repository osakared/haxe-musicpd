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
        MusicPD.connect('localhost').handle((outcome) -> {
            switch outcome {
                case Success(musicPD):
                    musicPD.listCommands().handle((response) -> {
                        switch response {
                            case Success(songs):
                                trace(songs.collection);
                            case Failure(err):
                                trace(err);
                        }
                    });
                case Failure(error):
                    trace(error);
            }
        });
        return assert(true);
    }
}