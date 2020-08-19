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
                    musicPD.getPlaylistChanges(0).handle((response) -> {
                        switch response {
                            case Success(songs):
                                trace(songs);
                                // var output = sys.io.File.write('/Users/pinkboi/tst.jpg');
                                // output.write(songs);
                                // output.close();
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