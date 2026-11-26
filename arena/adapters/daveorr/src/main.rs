//! Bot bridge adapter (doc/bot_bridge.md) for dave-orr/Tichu-ai.
//!
//!     daveorr_bridge BOT [SEED]      e.g. daveorr_bridge h2, daveorr_bridge eg:pimc10/h
//!
//! Every request is answered from a fresh shadow game: the round replayed
//! through their engine from the request's events, with the hidden hands
//! filled in by a guess that explains every card the others played and
//! passed. Only `view(seat)` of the shadow reaches the bot, so it sees what
//! it would see in their own arena. Each seat keeps its bot between
//! requests (bots may keep state).

use std::collections::HashMap;
use std::io::{BufRead, Write};

use rand::rngs::StdRng;
use rand::seq::SliceRandom;
use rand::SeedableRng;
use serde_json::{json, Value};
use tichu_engine::bot::Bot;
use tichu_engine::bots::by_name;
use tichu_engine::combinations::can_fulfill_wish;
use tichu_engine::engine::{Action, GameState, Pending};
use tichu_engine::types::*;

type Res<T> = Result<T, String>;

fn parse_card(code: &str) -> Res<Card> {
    Ok(match code {
        "MJ" => MAH_JONG,
        "DG" => DOG,
        "PH" => PHOENIX,
        "DR" => DRAGON,
        _ => {
            let b = code.as_bytes();
            if b.len() != 2 {
                return Err(format!("bad card {code}"));
            }
            let rank = match b[0] {
                b'2'..=b'9' => b[0] - b'0',
                b'T' => 10,
                b'J' => 11,
                b'Q' => 12,
                b'K' => 13,
                b'A' => 14,
                _ => return Err(format!("bad rank {code}")),
            };
            let suit = match b[1] {
                b'g' => Suit::Jade,
                b'b' => Suit::Sword,
                b'k' => Suit::Pagoda,
                b'r' => Suit::Star,
                _ => return Err(format!("bad suit {code}")),
            };
            Card::Normal { suit, rank }
        }
    })
}

fn card_code(c: Card) -> String {
    match c {
        Card::Special(SpecialKind::MahJong) => "MJ".into(),
        Card::Special(SpecialKind::Dog) => "DG".into(),
        Card::Special(SpecialKind::Phoenix) => "PH".into(),
        Card::Special(SpecialKind::Dragon) => "DR".into(),
        Card::Normal { suit, rank } => {
            let r = b"..23456789TJQKA"[rank as usize] as char;
            let s = match suit {
                Suit::Jade => 'g',
                Suit::Sword => 'b',
                Suit::Pagoda => 'k',
                Suit::Star => 'r',
            };
            format!("{r}{s}")
        }
    }
}

fn cards(v: &Value) -> Res<Vec<Card>> {
    v.as_array()
        .ok_or("expected a card list")?
        .iter()
        .map(|c| parse_card(c.as_str().unwrap_or("")))
        .collect()
}

fn seat(v: &Value) -> Res<Seat> {
    v.as_u64().map(|s| s as Seat).ok_or_else(|| format!("bad seat {v}"))
}

fn rank_of(code: &str) -> Res<Rank> {
    match parse_card(&format!("{code}g"))? {
        Card::Normal { rank, .. } => Ok(rank),
        _ => Err(format!("bad rank {code}")),
    }
}

fn kind_name(k: ComboKind) -> &'static str {
    match k {
        ComboKind::Single => "single",
        ComboKind::Pair => "pair",
        ComboKind::Triple => "triple",
        ComboKind::FullHouse => "full_house",
        ComboKind::Straight => "straight",
        ComboKind::ConsecutivePairs => "pair_straight",
        ComboKind::FourOfAKindBomb | ComboKind::StraightFlushBomb => "bomb",
    }
}

/// Our combination type of `c` (we call the Dog its own type).
fn combo_type(c: &Combo) -> &'static str {
    if c.cards == [DOG] { "dog" } else { kind_name(c.kind) }
}

fn same_cards(a: &[Card], b: &[Card]) -> bool {
    let mut a: Vec<String> = a.iter().map(|&c| card_code(c)).collect();
    let mut b: Vec<String> = b.iter().map(|&c| card_code(c)).collect();
    a.sort();
    b.sort();
    a == b
}

/// Ranks of `cards`, sorted (specials by name): suits aside, what a
/// combination is.
fn rank_key(cards: &[Card]) -> Vec<String> {
    let mut k: Vec<String> = cards
        .iter()
        .map(|&c| match c {
            Card::Normal { .. } => card_code(c)[..1].to_string(),
            _ => card_code(c),
        })
        .collect();
    k.sort();
    k
}

/// The combination of `plays` that is our `(cards, type, value)`.
fn find_combo<'a>(plays: &'a [Combo], cards: &[Card], kind: &str, value: f64) -> Option<&'a Combo> {
    let matches: Vec<&Combo> =
        plays.iter().filter(|c| combo_type(c) == kind && same_cards(&c.cards, cards)).collect();
    if matches.len() <= 1 || kind == "single" || kind == "dog" {
        return matches.first().copied();
    }
    // A Phoenix that can stand for two ranks: tell them apart by value.
    matches.iter().copied().find(|c| (c.rank as f64 - value).abs() < 0.01).or(matches.first().copied())
}

fn remove(hand: &mut Vec<Card>, c: Card) -> Res<()> {
    let i = hand.iter().position(|&h| h == c).ok_or_else(|| format!("{} not in hand", card_code(c)))?;
    hand.swap_remove(i);
    Ok(())
}

/// Replays the request's round into a fresh `GameState`.
fn shadow(state: &Value, rng: &mut StdRng) -> Res<GameState> {
    let me = seat(&state["seat"])?;
    let events = state["events"].as_array().ok_or("no events")?;
    let first_mine = cards(&state["first_cards"])?;
    let dealt_mine = match state.get("dealt") {
        Some(d) => Some(cards(d)?),
        None => None,
    };
    let round = &events[0];
    let mut played: [Vec<Card>; 4] = Default::default();
    let mut my_give: HashMap<Seat, Card> = HashMap::new();
    let mut to_me: HashMap<Seat, Card> = HashMap::new();
    for ev in events {
        match ev["e"].as_str().unwrap_or("") {
            "play" => played[seat(&ev["seat"])?].extend(cards(&ev["cards"])?),
            "schupf" if seat(&ev["seat"])? == me => {
                for (k, c) in ev["give"].as_object().ok_or("no give")? {
                    my_give.insert(k.parse().map_err(|_| "bad seat")?, parse_card(c.as_str().unwrap_or(""))?);
                }
            }
            "schupf_received" => {
                for (k, c) in ev["from"].as_object().ok_or("no from")? {
                    to_me.insert(k.parse().map_err(|_| "bad seat")?, parse_card(c.as_str().unwrap_or(""))?);
                }
            }
            _ => {}
        }
    }

    // The deal: what each seat held before the pass (first 8, then 6).
    let others: Vec<Seat> = (0..4).filter(|&s| s != me).collect();
    let mut dealt: [Vec<Card>; 4] = Default::default();
    // What each other seat passed to every other seat.
    let mut gifts: HashMap<(Seat, Seat), Card> = HashMap::new();
    let mut pool: Vec<Card> = tichu_engine::deck::shuffled_deck(rng);
    match &dealt_mine {
        None => {
            pool.retain(|c| !first_mine.contains(c));
            dealt[me] = first_mine.clone();
            for &s in &others {
                dealt[s] = pool.drain(..8).collect();
            }
        }
        Some(mine) if to_me.is_empty() => {
            pool.retain(|c| !mine.contains(c));
            dealt[me] = mine.clone();
            for &s in &others {
                dealt[s] = pool.drain(..14).collect();
            }
        }
        Some(mine) => {
            // After the pass: each other seat's hand must hold what it played
            // and what I passed it; then undo the pass to get its deal.
            let mut after: [Vec<Card>; 4] = Default::default();
            for &s in &others {
                after[s] = played[s].clone();
                if !after[s].contains(&my_give[&s]) {
                    after[s].push(my_give[&s]);
                }
            }
            // The first to play held the Mah Jong (unless it is with me).
            let first = events.iter().find(|e| e["e"] == "play").map(|e| seat(&e["seat"])).transpose()?;
            if let Some(f) = first {
                let with_me = mine.contains(&MAH_JONG) || to_me.values().any(|&c| c == MAH_JONG);
                if f != me && !with_me && !after[f].contains(&MAH_JONG) {
                    after[f].push(MAH_JONG);
                }
            }
            pool.retain(|c| {
                !mine.contains(c)
                    && !to_me.values().any(|x| x == c)
                    && !others.iter().any(|&s| after[s].contains(c))
            });
            for &s in &others {
                let n = 14 - after[s].len();
                after[s].extend(pool.drain(..n));
            }
            for &y in &others {
                // y got one card from each other seat; pick them from its hand.
                let mut spare: Vec<Card> = after[y].iter().copied().filter(|&c| c != my_give[&y]).collect();
                spare.shuffle(rng);
                for &x in others.iter().filter(|&&x| x != y) {
                    gifts.insert((x, y), spare.pop().ok_or("no card to pass")?);
                }
            }
            dealt[me] = mine.clone();
            for &x in &others {
                let mut h = after[x].clone();
                remove(&mut h, my_give[&x])?;
                for &y in others.iter().filter(|&&y| y != x) {
                    remove(&mut h, gifts[&(y, x)])?;
                    h.push(gifts[&(x, y)]);
                }
                h.push(to_me[&x]);
                dealt[x] = h;
            }
        }
    }
    // Our first 8 must stay our first 8.
    if dealt_mine.is_some() {
        let mut rest = dealt[me].clone();
        for &c in &first_mine {
            remove(&mut rest, c)?;
        }
        dealt[me] = first_mine.iter().copied().chain(rest).collect();
    }
    let mut deck = Vec::with_capacity(56);
    let mut spare: Vec<Card> = tichu_engine::deck::shuffled_deck(rng);
    spare.retain(|c| !dealt.iter().any(|h| h.contains(c)));
    for s in 0..4 {
        let mut h = dealt[s].clone();
        while h.len() < 14 {
            h.push(spare.pop().ok_or("deck ran out")?);
        }
        deck.extend(h);
    }

    let target = state["target_score"].as_i64().unwrap_or(1000) as i32;
    let mut g = GameState::new(Settings { clockwise: false, target_score: target });
    g.scores = [round["scores"][0].as_i64().unwrap_or(0) as i32, round["scores"][1].as_i64().unwrap_or(0) as i32];
    g.round_number = round["round"].as_u64().unwrap_or(1).saturating_sub(1) as u32;
    g.start_round(deck);

    let mut early_tichu: Vec<Seat> = vec![];
    let apply = |g: &mut GameState, a: Action| g.apply(&a).map_err(|e| format!("{a:?}: {e:?}"));
    for ev in &events[1..] {
        match ev["e"].as_str().unwrap_or("") {
            "grand" => {
                let s = seat(&ev["seat"])?;
                let call = ev["call"].as_bool().unwrap_or(false);
                if g.players[s].grand_decided {
                    // A Grand call after deciding no can't happen in their engine.
                    return Err("second Grand Tichu decision".into());
                }
                apply(&mut g, Action::GrandTichu { seat: s, call })?;
            }
            "tichu" => {
                let s = seat(&ev["seat"])?;
                if g.phase == Phase::Playing && g.out_count > 0 {
                    // Our rules allow a (hopeless) call after someone is out;
                    // theirs don't: record it by hand.
                    g.players[s].tichu = TichuCall::Small;
                } else if g.phase == Phase::Playing {
                    apply(&mut g, Action::SmallTichu { seat: s })?;
                } else {
                    // Their engine takes Tichu calls once play begins.
                    early_tichu.push(s);
                }
            }
            "schupf" => {
                let s = seat(&ev["seat"])?;
                let to = |d: Seat| -> Card {
                    let r = (s + d) % 4;
                    if s == me { my_give[&r] } else if r == me { to_me[&s] } else { gifts[&(s, r)] }
                };
                let pass = if s == me || !to_me.is_empty() {
                    PassInfo { right: to(1), partner: to(2), left: to(3) }
                } else {
                    // Before the exchange others' passes are unknown: any 3 cards.
                    let h = &g.players[s].hand;
                    PassInfo { right: h[0], partner: h[1], left: h[2] }
                };
                apply(&mut g, Action::PassCards { seat: s, pass })?;
                if g.phase == Phase::Playing {
                    for s in early_tichu.drain(..) {
                        apply(&mut g, Action::SmallTichu { seat: s })?;
                    }
                }
            }
            "play" => {
                let s = seat(&ev["seat"])?;
                let cs = cards(&ev["cards"])?;
                let kind = ev["type"].as_str().unwrap_or("");
                let value = ev["value"].as_f64().unwrap_or(0.0);
                let mut plays = g.legal_plays(s);
                if s != me && g.wish.is_some() && find_combo(&plays, &cs, kind, value).is_none() {
                    // Not the wish: the guess must not let s fulfil it.
                    explain_wish_pass(&mut g, s, me, &played, &my_give, rng)?;
                    plays = g.legal_plays(s);
                }
                let combo = find_combo(&plays, &cs, kind, value).ok_or_else(|| {
                    format!("seat {s} played {:?} ({kind}), not legal in their engine", ev["cards"])
                })?;
                let a = Action::Play { seat: s, cards: combo.cards.clone(), phoenix_as: combo.phoenix_as };
                apply(&mut g, a)?;
                if matches!(g.pending(), Pending::Wish(_)) {
                    let rank = match ev.get("wish").and_then(|w| w.as_str()) {
                        Some(w) => Some(rank_of(w)?),
                        None => None,
                    };
                    apply(&mut g, Action::Wish { seat: s, rank })?;
                }
            }
            "pass" => {
                let s = seat(&ev["seat"])?;
                let pass = Action::PassTurn { seat: s };
                if s != me && g.apply(&pass).is_err() {
                    // The guess gave s a card that fulfils the wish; it had none.
                    explain_wish_pass(&mut g, s, me, &played, &my_give, rng)?;
                }
                if g.log.last() != Some(&pass) {
                    apply(&mut g, pass)?;
                }
            }
            "dragon" => {
                apply(&mut g, Action::GiveDragon { seat: seat(&ev["seat"])?, to: seat(&ev["to"])? })?;
            }
            "schupf_received" => {}
            other => return Err(format!("unknown event {other}")),
        }
        while matches!(g.pending(), Pending::TrickCountdown(_)) {
            apply(&mut g, Action::ResolveTrick)?;
        }
    }
    Ok(g)
}

/// Swaps cards between hidden seat `s`'s guessed hand and the other hidden
/// hands until `s` cannot fulfil the wish, so that its pass (or a play
/// without the wished rank) is legal. Cards
/// a seat plays later stay with it, and so do the cards I passed it.
fn explain_wish_pass(
    g: &mut GameState,
    s: Seat,
    me: Seat,
    played: &[Vec<Card>; 4],
    my_give: &HashMap<Seat, Card>,
    rng: &mut StdRng,
) -> Res<()> {
    use rand::Rng;
    let w = g.wish.ok_or("pass refused without a wish")?;
    let fixed = |seat: Seat, c: &Card| played[seat].contains(c) || my_give.get(&seat) == Some(c);
    let is_w = |c: &Card| matches!(c, Card::Normal { rank, .. } if *rank == w);
    let others: Vec<Seat> = (0..4).filter(|&y| y != s && y != me && !g.players[y].hand.is_empty()).collect();
    for _ in 0..2000 {
        if !can_fulfill_wish(&g.players[s].hand, w, g.current_trick.as_ref()) {
            return Ok(());
        }
        // Wished cards first, then any card of s that is free to move.
        let mine: Vec<Card> = g.players[s].hand.iter().copied().filter(|c| !fixed(s, c)).collect();
        let pick: Vec<Card> = mine.iter().copied().filter(|c| is_w(c)).collect();
        let pick = if pick.is_empty() { mine } else { pick };
        if pick.is_empty() || others.is_empty() {
            break;
        }
        let c = pick[rng.gen_range(0..pick.len())];
        let y = others[rng.gen_range(0..others.len())];
        let theirs: Vec<Card> = g.players[y].hand.iter().copied().filter(|d| !fixed(y, d) && !is_w(d)).collect();
        if theirs.is_empty() {
            continue;
        }
        let d = theirs[rng.gen_range(0..theirs.len())];
        remove(&mut g.players[s].hand, c)?;
        remove(&mut g.players[y].hand, d)?;
        g.players[s].hand.push(d);
        g.players[y].hand.push(c);
        tichu_engine::deck::sort_hand(&mut g.players[s].hand);
        tichu_engine::deck::sort_hand(&mut g.players[y].hand);
    }
    Err(format!("no guess lets seat {s} pass under the wish"))
}

struct Adapter {
    spec: String,
    seed: u64,
    bots: HashMap<Seat, Box<dyn Bot>>,
    rng: StdRng,
}

impl Adapter {
    fn decide(&mut self, req: &Value) -> Res<Value> {
        let state = &req["state"];
        let me = seat(&state["seat"])?;
        let g = shadow(state, &mut self.rng)?;
        if !same_cards(&g.players[me].hand, &cards(&state["hand"])?) {
            return Err("shadow hand differs from the real one".into());
        }
        let spec = self.spec.clone();
        let seed = self.seed + me as u64;
        let bot = self
            .bots
            .entry(me)
            .or_insert_with(|| by_name(&spec, seed).unwrap_or_else(|| panic!("unknown bot {spec}")));
        let view = g.view(me);
        Ok(match req["type"].as_str().unwrap_or("") {
            "grand" => json!({"call": bot.grand_tichu(&view)}),
            "tichu" => {
                let call = req["phase"] == "play" && g.can_call_small_tichu(me) && bot.small_tichu(&view);
                json!({"call": call})
            }
            "schupf" => {
                let p = bot.pass_cards(&view);
                json!({"give": {
                    ((me + 1) % 4).to_string(): card_code(p.right),
                    ((me + 2) % 4).to_string(): card_code(p.partner),
                    ((me + 3) % 4).to_string(): card_code(p.left),
                }})
            }
            "play" => {
                if !matches!(g.pending(), Pending::Turn(s) if s == me) {
                    return Err(format!("not our turn in their engine: {:?}", g.pending()));
                }
                let plays = g.legal_plays(me);
                let can_pass = g.can_pass(me);
                let choice = bot.play(&view, &plays, can_pass);
                let Some(i) = choice else {
                    return Ok(json!({"option": Value::Null}));
                };
                let combo = &plays[i];
                let options = req["options"].as_array().ok_or("no options")?;
                // Exact cards first; else the same ranks (our move generator
                // lists one suit variant of straights and pairs; suits only
                // matter for bombs, which always match exactly).
                let mut exact = None;
                let mut by_rank = None;
                for (j, o) in options.iter().enumerate() {
                    if o["type"] != combo_type(combo) {
                        continue;
                    }
                    let oc = cards(&o["cards"])?;
                    let same_value = (o["value"].as_f64().unwrap_or(0.0) - combo.rank as f64).abs() < 0.01
                        || combo.kind == ComboKind::Single;
                    let same_value = same_value || combo.cards == [DOG];
                    if same_cards(&oc, &combo.cards) && (same_value || exact.is_none()) {
                        exact = Some(j);
                    } else if !combo.is_bomb() && same_value && by_rank.is_none() && rank_key(&oc) == rank_key(&combo.cards) {
                        by_rank = Some(j);
                    }
                }
                let j = exact.or(by_rank).ok_or_else(|| {
                    format!("their bot chose {:?} ({:?} {}), not among our options", combo.cards.iter().map(|&c| card_code(c)).collect::<Vec<_>>(), combo.kind, combo.rank)
                })?;
                let mut reply = json!({"option": j});
                if combo.cards.contains(&MAH_JONG) {
                    let mut after = g.clone();
                    after
                        .apply(&Action::Play { seat: me, cards: combo.cards.clone(), phoenix_as: combo.phoenix_as })
                        .map_err(|e| format!("{e:?}"))?;
                    let wish = bot.wish(&after.view(me));
                    reply["wish"] = match wish {
                        Some(r) => json!(card_code(Card::Normal { suit: Suit::Jade, rank: r })[..1]),
                        None => Value::Null,
                    };
                }
                reply
            }
            "dragon" => {
                if !matches!(g.pending(), Pending::DragonGiveaway(s) if s == me) {
                    return Err(format!("no Dragon gift pending in their engine: {:?}", g.pending()));
                }
                json!({"to": bot.dragon_recipient(&view)})
            }
            other => return Err(format!("unknown request {other}")),
        })
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let spec = args.get(1).cloned().unwrap_or_else(|| "h2".into());
    let seed: u64 = args.get(2).and_then(|s| s.parse().ok()).unwrap_or(1);
    if by_name(&spec, seed).is_none() {
        eprintln!("unknown bot {spec}");
        std::process::exit(2);
    }
    let mut ad = Adapter { spec, seed, bots: HashMap::new(), rng: StdRng::seed_from_u64(seed) };
    let stdin = std::io::stdin();
    let mut out = std::io::stdout().lock();
    for line in stdin.lock().lines() {
        let line = line.expect("stdin");
        let req: Value = serde_json::from_str(&line).expect("request JSON");
        let mut reply = match ad.decide(&req) {
            Ok(r) => r,
            Err(e) => {
                // BRIDGE_DUMP=file keeps the requests that failed, to replay.
                if let Ok(path) = std::env::var("BRIDGE_DUMP") {
                    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
                        let _ = writeln!(f, "{line}");
                    }
                }
                json!({"error": e})
            }
        };
        reply["id"] = req["id"].clone();
        writeln!(out, "{reply}").expect("stdout");
        out.flush().expect("stdout");
    }
}
