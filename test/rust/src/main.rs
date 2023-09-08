extern crate fancy_regex;
use fancy_regex::Regex;
fn main() {
    let re = Regex::new(r"(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}{1,3}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+").unwrap();
    let hays = [
        "llo",
    ];
    for hay in hays.iter() {
        for mat in re.find_iter(hay) {
            print!("{:?} ", mat.expect("").as_str());
        }
        println!("");
    }
}
