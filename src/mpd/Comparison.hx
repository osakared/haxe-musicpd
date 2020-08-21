package mpd;

/**
 * Comparison to use when searching based on tags
 */
enum abstract Comparison(String)
{
    var EqualComparison = '=';
    var LessComparison = '<';
    var GreaterComparison = '>';
}