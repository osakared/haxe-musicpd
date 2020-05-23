package;

import tink.unit.TestBatch;
import tink.testrunner.*;
import test.unit.*;

class RunTests
{
    static function main()
    {
        Runner.run(TestBatch.make([
            new ConnectionTest()
        ])).handle(Runner.exit);
    }
}