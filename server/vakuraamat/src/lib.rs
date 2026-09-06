//! Vakuraamat town ledger. One SpacetimeDB database per town (a 1 km² tile of real Estonian parcels).
//! Terrain, buildings and trees never travel: every client regenerates them from Maa-amet data; only
//! this ledger is shared. Every mutation is validated here; error strings are the game's translation keys.
//! Money is whole euros. The economic period is a month, advanced by the scheduled `tick` while someone
//! is online. Seeding is an admin step (`tools/town_admin.py`), done by the identity that published.
use vakuraamat_rules as rules;

use spacetimedb::rand::Rng;
use spacetimedb::{reducer, table, Identity, ReducerContext, ScheduleAt, Table, Timestamp};
use std::time::Duration;

pub const EVENT_KEEP: usize = 300;
pub const PRESENCE_STALE_MICROS: i64 = 90_000_000;
pub const BID_LIFE_MONTHS: u32 = 3;

#[table(accessor = town, public)]
#[derive(Clone)]
pub struct Town {
    #[primary_key]
    pub id: u32,
    pub pack_id: String,
    pub pack_hash: String,
    pub month: u32,
    pub seconds_per_month: u32,
    pub price_index_permille: u32,
    pub seeded: bool,
    pub debug: bool,
    pub admin: Identity,
    pub created: Timestamp,
}

#[table(accessor = economy_config)]
#[derive(Clone)]
pub struct EconomyConfig {
    #[primary_key]
    pub id: u32,
    pub starting_cash: i64,
    pub tax_rate_year_permille: u32,
    pub arrears_chance_permille: u32,
    pub arrears_chance_bad_status_permille: u32,
    pub drift_permille: u32,
    pub ai_bid_chance_permille: u32,
    pub obligation_grace_months: u32,
    pub penalty_permille: u32,
    pub families: Vec<String>,
}

#[table(accessor = parcel, public)]
#[derive(Clone)]
pub struct Parcel {
    #[primary_key]
    pub tunnus: String,
    pub address: String,
    pub purpose: String,
    pub area: u32,
    pub land_value: u64,
    pub price: u64,
    pub rent_month: u64,
    #[index(btree)]
    pub owner_id: u64,
    pub owner_name: String,
    pub for_sale: bool,
    pub sellable: bool,
    pub x: f32,
    pub z: f32,
}

#[table(accessor = tenant, public)]
#[derive(Clone)]
pub struct Tenant {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub tunnus: String,
    pub name: String,
    pub registry_code: String,
    pub legal_form: String,
    pub status: String,
    pub since: String,
    pub arrears: u64,
    pub sector: String,     // the game's EMTAK group (trade, services, ...), "" when unknown
    pub employees: u32,     // latest Tax Board quarter
    pub turnover: u64,      // last four quarters, euros
    pub health: String,     // sound | watch | distressed
}

#[table(accessor = player, public)]
#[derive(Clone)]
pub struct Player {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[unique]
    pub identity: Identity,
    pub name: String,
    pub cash: i64,
    pub favours: i32,
    pub heat: i32,
    pub reputation: i32,
    pub online: bool,
    pub joined_month: u32,
    pub last_seen: Timestamp,
}

#[table(accessor = presence, public)]
#[derive(Clone)]
pub struct Presence {
    #[primary_key]
    pub player_id: u64,
    pub x: f32,
    pub z: f32,
    pub yaw: f32,
    pub updated: Timestamp,
}

#[table(accessor = bid, public)]
#[derive(Clone)]
pub struct Bid {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub tunnus: String,
    pub bidder_id: u64,
    pub bidder_name: String,
    pub amount: u64,
    pub placed_month: u32,
    pub expires_month: u32,
    pub status: u8, // 0 open, 1 accepted, 2 rejected, 3 withdrawn, 4 expired
}

#[table(accessor = obligation, public)]
#[derive(Clone)]
pub struct Obligation {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub player_id: u64,
    pub kind: String, // land_tax | penalty
    pub tunnus: String,
    pub amount: u64,
    pub due_month: u32,
    pub paid: bool,
}

#[table(accessor = structure, public)]
#[derive(Clone)]
pub struct Structure {
    #[primary_key]
    pub id: String,
    pub cost: u64,
    pub rent_bonus: u64,
    pub requires: String,
    pub purposes: String, // comma separated purpose codes, empty = any
}

#[table(accessor = improvement, public)]
#[derive(Clone)]
pub struct Improvement {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    #[index(btree)]
    pub tunnus: String,
    pub structure_id: String,
    pub player_id: u64,
    pub built_month: u32,
}

#[table(accessor = event, public)]
#[derive(Clone)]
pub struct Event {
    #[primary_key]
    #[auto_inc]
    pub id: u64,
    pub month: u32,
    pub kind: String, // news | official | macro | sale | rent | bid | tax | build | tick | join
    pub title: String,
    pub source: String,
    pub link: String,
    pub tunnus: String,
    pub actor_id: u64,
    pub amount: i64,
    pub published: String,
    pub at: Timestamp,
}

#[table(accessor = tick_schedule, scheduled(tick))]
#[derive(Clone)]
pub struct TickSchedule {
    #[primary_key]
    #[auto_inc]
    pub scheduled_id: u64,
    pub scheduled_at: ScheduleAt,
}

// ---------------------------------------------------------------- helpers

fn town(ctx: &ReducerContext) -> Result<Town, String> {
    ctx.db.town().id().find(0).ok_or_else(|| "LEDGER_NOT_SEEDED".to_string())
}

fn config(ctx: &ReducerContext) -> Result<EconomyConfig, String> {
    ctx.db.economy_config().id().find(0).ok_or_else(|| "LEDGER_NOT_SEEDED".to_string())
}

fn me(ctx: &ReducerContext) -> Result<Player, String> {
    ctx.db.player().identity().find(ctx.sender()).ok_or_else(|| "LEDGER_NOT_JOINED".to_string())
}

fn require_admin(ctx: &ReducerContext) -> Result<Town, String> {
    let t = town(ctx)?;
    if t.admin != ctx.sender() {
        return Err("LEDGER_NOT_ADMIN".to_string());
    }
    Ok(t)
}

fn parcel(ctx: &ReducerContext, tunnus: &str) -> Result<Parcel, String> {
    ctx.db.parcel().tunnus().find(tunnus.to_string()).ok_or_else(|| "LEDGER_NO_PARCEL".to_string())
}

fn push_event(ctx: &ReducerContext, month: u32, kind: &str, title: String, source: &str, link: &str, tunnus: &str, actor_id: u64, amount: i64, published: &str) {
    ctx.db.event().insert(Event {
        id: 0,
        month,
        kind: kind.to_string(),
        title,
        source: source.to_string(),
        link: link.to_string(),
        tunnus: tunnus.to_string(),
        actor_id,
        amount,
        published: published.to_string(),
        at: ctx.timestamp,
    });
}

fn prune_events(ctx: &ReducerContext) {
    let mut ids: Vec<u64> = ctx.db.event().iter().map(|e| e.id).collect();
    if ids.len() <= EVENT_KEEP {
        return;
    }
    ids.sort_unstable();
    for id in ids.iter().take(ids.len() - EVENT_KEEP) {
        ctx.db.event().id().delete(*id);
    }
}

fn credit(ctx: &ReducerContext, mut p: Player, delta: i64) -> Player {
    p.cash += delta;
    ctx.db.player().id().update(p.clone());
    p
}

fn player_by_id(ctx: &ReducerContext, id: u64) -> Option<Player> {
    ctx.db.player().id().find(id)
}

fn transfer(ctx: &ReducerContext, mut par: Parcel, buyer: &Player, amount: u64, month: u32, how: &str) {
    if par.owner_id != 0 {
        if let Some(prev) = player_by_id(ctx, par.owner_id) {
            credit(ctx, prev, amount as i64);
        }
    }
    par.owner_id = buyer.id;
    par.owner_name = buyer.name.clone();
    par.for_sale = false;
    par.price = amount;
    let tunnus = par.tunnus.clone();
    let address = par.address.clone();
    ctx.db.parcel().tunnus().update(par);
    for b in ctx.db.bid().tunnus().filter(&tunnus).collect::<Vec<_>>() {
        if b.status == 0 {
            ctx.db.bid().id().update(Bid { status: 2, ..b });
        }
    }
    push_event(ctx, month, "sale", format!("{} {} ({})", how, address, tunnus), "", "", &tunnus, buyer.id, amount as i64, "");
}

// ---------------------------------------------------------------- lifecycle

#[reducer(init)]
pub fn init(ctx: &ReducerContext) {
    ctx.db.town().insert(Town {
        id: 0,
        pack_id: String::new(),
        pack_hash: String::new(),
        month: 0,
        seconds_per_month: 600,
        price_index_permille: 1000,
        seeded: false,
        debug: false,
        admin: ctx.sender(),
        created: ctx.timestamp,
    });
    ctx.db.tick_schedule().insert(TickSchedule { scheduled_id: 0, scheduled_at: ScheduleAt::Interval(Duration::from_secs(600).into()) });
    log::info!("town created by {}", ctx.sender());
}

#[reducer(client_connected)]
pub fn on_connect(ctx: &ReducerContext) {
    if let Some(p) = ctx.db.player().identity().find(ctx.sender()) {
        ctx.db.player().id().update(Player { online: true, last_seen: ctx.timestamp, ..p });
    }
}

#[reducer(client_disconnected)]
pub fn on_disconnect(ctx: &ReducerContext) {
    if let Some(p) = ctx.db.player().identity().find(ctx.sender()) {
        ctx.db.presence().player_id().delete(p.id);
        ctx.db.player().id().update(Player { online: false, last_seen: ctx.timestamp, ..p });
    }
}

// ---------------------------------------------------------------- seeding (admin)

#[reducer]
pub fn seed_config(
    ctx: &ReducerContext, pack_id: String, pack_hash: String, seconds_per_month: u32, debug: bool, starting_cash: i64, tax_rate_year_permille: u32,
    arrears_chance_permille: u32, arrears_chance_bad_status_permille: u32, drift_permille: u32, ai_bid_chance_permille: u32, obligation_grace_months: u32,
    penalty_permille: u32, families: String,
) -> Result<(), String> {
    let t = require_admin(ctx)?;
    let cfg = EconomyConfig {
        id: 0,
        starting_cash,
        tax_rate_year_permille,
        arrears_chance_permille,
        arrears_chance_bad_status_permille,
        drift_permille,
        ai_bid_chance_permille,
        obligation_grace_months,
        penalty_permille,
        families: families.split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect(),
    };
    if ctx.db.economy_config().id().find(0).is_some() {
        ctx.db.economy_config().id().update(cfg);
    } else {
        ctx.db.economy_config().insert(cfg);
    }
    ctx.db.town().id().update(Town { pack_id, pack_hash, seconds_per_month: seconds_per_month.max(10), debug, ..t });
    for s in ctx.db.tick_schedule().iter().collect::<Vec<_>>() {
        ctx.db.tick_schedule().scheduled_id().update(TickSchedule {
            scheduled_at: ScheduleAt::Interval(Duration::from_secs(seconds_per_month.max(10) as u64).into()),
            ..s
        });
    }
    Ok(())
}

/// Insert or refresh one parcel. Existing owned parcels keep owner and price; unowned ones follow the new value.
#[reducer]
pub fn seed_parcel(
    ctx: &ReducerContext, tunnus: String, address: String, purpose: String, area: u32, land_value: u64, rent_month: u64, owner_name: String, sellable: bool, x: f32, z: f32,
) -> Result<(), String> {
    let t = require_admin(ctx)?;
    let price = rules::list_price(land_value, t.price_index_permille);
    match ctx.db.parcel().tunnus().find(&tunnus) {
        Some(p) if p.owner_id != 0 => {
            ctx.db.parcel().tunnus().update(Parcel { address, purpose, area, land_value, rent_month, sellable, x, z, ..p });
        }
        Some(p) => {
            ctx.db.parcel().tunnus().update(Parcel { address, purpose, area, land_value, price, rent_month, owner_name, sellable, x, z, ..p });
        }
        None => {
            ctx.db.parcel().insert(Parcel { tunnus, address, purpose, area, land_value, price, rent_month, owner_id: 0, owner_name, for_sale: sellable, sellable, x, z });
        }
    }
    Ok(())
}

#[reducer]
pub fn clear_tenants(ctx: &ReducerContext, tunnus: String) -> Result<(), String> {
    require_admin(ctx)?;
    for t in ctx.db.tenant().tunnus().filter(&tunnus).collect::<Vec<_>>() {
        ctx.db.tenant().id().delete(t.id);
    }
    Ok(())
}

#[reducer]
pub fn seed_tenant(
    ctx: &ReducerContext, tunnus: String, name: String, registry_code: String, legal_form: String, status: String, since: String, sector: String,
    employees: u32, turnover: u64, health: String,
) -> Result<(), String> {
    require_admin(ctx)?;
    if ctx.db.tenant().iter().any(|t| t.registry_code == registry_code) {
        return Ok(());
    }
    ctx.db.tenant().insert(Tenant { id: 0, tunnus, name, registry_code, legal_form, status, since, arrears: 0, sector, employees, turnover, health });
    Ok(())
}

#[reducer]
pub fn seed_structure(ctx: &ReducerContext, id: String, cost: u64, rent_bonus: u64, requires: String, purposes: String) -> Result<(), String> {
    require_admin(ctx)?;
    let s = Structure { id: id.clone(), cost, rent_bonus, requires, purposes };
    if ctx.db.structure().id().find(&id).is_some() {
        ctx.db.structure().id().update(s);
    } else {
        ctx.db.structure().insert(s);
    }
    Ok(())
}

#[reducer]
pub fn finish_seed(ctx: &ReducerContext) -> Result<(), String> {
    let t = require_admin(ctx)?;
    config(ctx)?;
    let n = ctx.db.parcel().count();
    if n == 0 {
        return Err("LEDGER_NO_PARCELS".to_string());
    }
    ctx.db.town().id().update(Town { seeded: true, ..t });
    push_event(ctx, 0, "tick", format!("Town opened with {} parcels", n), "", "", "", 0, 0, "");
    log::info!("seeded: {} parcels, {} tenants, {} structures", n, ctx.db.tenant().count(), ctx.db.structure().count());
    Ok(())
}

/// The news feeder (admin identity) posts one real-world or macro item.
#[reducer]
pub fn post_event(ctx: &ReducerContext, kind: String, title: String, source: String, link: String, tunnus: String, published: String) -> Result<(), String> {
    let t = require_admin(ctx)?;
    if !matches!(kind.as_str(), "news" | "official" | "macro") {
        return Err("LEDGER_BAD_EVENT_KIND".to_string());
    }
    if ctx.db.event().iter().any(|e| e.kind == kind && e.link == link && !link.is_empty()) {
        return Ok(());
    }
    push_event(ctx, t.month, &kind, title, &source, &link, &tunnus, 0, 0, &published);
    prune_events(ctx);
    Ok(())
}

// ---------------------------------------------------------------- players

#[reducer]
pub fn join_town(ctx: &ReducerContext, pack_hash: String, name: String) -> Result<(), String> {
    let t = town(ctx)?;
    if !t.seeded {
        return Err("LEDGER_NOT_SEEDED".to_string());
    }
    if !t.pack_hash.is_empty() && t.pack_hash != pack_hash {
        return Err("LEDGER_HASH_MISMATCH".to_string());
    }
    let name = name.trim().chars().take(24).collect::<String>();
    if let Some(p) = ctx.db.player().identity().find(ctx.sender()) {
        ctx.db.player().id().update(Player { online: true, last_seen: ctx.timestamp, name: if name.is_empty() { p.name.clone() } else { name }, ..p });
        return Ok(());
    }
    let cfg = config(ctx)?;
    let p = ctx.db.player().insert(Player {
        id: 0,
        identity: ctx.sender(),
        name: if name.is_empty() { "Player".to_string() } else { name },
        cash: cfg.starting_cash,
        favours: 0,
        heat: 0,
        reputation: 0,
        online: true,
        joined_month: t.month,
        last_seen: ctx.timestamp,
    });
    push_event(ctx, t.month, "join", format!("{} joined the town", p.name), "", "", "", p.id, 0, "");
    Ok(())
}

#[reducer]
pub fn set_name(ctx: &ReducerContext, name: String) -> Result<(), String> {
    let p = me(ctx)?;
    let name = name.trim().chars().take(24).collect::<String>();
    if name.is_empty() {
        return Err("LEDGER_BAD_NAME".to_string());
    }
    ctx.db.player().id().update(Player { name, ..p });
    Ok(())
}

#[reducer]
pub fn move_to(ctx: &ReducerContext, x: f32, z: f32, yaw: f32) -> Result<(), String> {
    let p = me(ctx)?;
    let row = Presence { player_id: p.id, x, z, yaw, updated: ctx.timestamp };
    if ctx.db.presence().player_id().find(p.id).is_some() {
        ctx.db.presence().player_id().update(row);
    } else {
        ctx.db.presence().insert(row);
    }
    Ok(())
}

// ---------------------------------------------------------------- market

#[reducer]
pub fn buy_parcel(ctx: &ReducerContext, tunnus: String) -> Result<(), String> {
    let t = town(ctx)?;
    let p = me(ctx)?;
    let par = parcel(ctx, &tunnus)?;
    if par.owner_id == p.id {
        return Err("LEDGER_ALREADY_OWNER".to_string());
    }
    if !par.sellable || !par.for_sale {
        return Err("LEDGER_NOT_FOR_SALE".to_string());
    }
    if p.cash < par.price as i64 {
        return Err("LEDGER_NO_MONEY".to_string());
    }
    let price = par.price;
    let buyer = credit(ctx, p, -(price as i64));
    transfer(ctx, par, &buyer, price, t.month, "Sold");
    Ok(())
}

#[reducer]
pub fn list_for_sale(ctx: &ReducerContext, tunnus: String, price: u64) -> Result<(), String> {
    let p = me(ctx)?;
    let par = parcel(ctx, &tunnus)?;
    if par.owner_id != p.id {
        return Err("LEDGER_NOT_OWNER".to_string());
    }
    if price == 0 {
        ctx.db.parcel().tunnus().update(Parcel { for_sale: false, ..par });
    } else {
        ctx.db.parcel().tunnus().update(Parcel { for_sale: true, price, ..par });
    }
    Ok(())
}

#[reducer]
pub fn place_bid(ctx: &ReducerContext, tunnus: String, amount: u64) -> Result<(), String> {
    let t = town(ctx)?;
    let p = me(ctx)?;
    let par = parcel(ctx, &tunnus)?;
    if par.owner_id == 0 || par.owner_id == p.id {
        return Err("LEDGER_NOT_BIDDABLE".to_string());
    }
    if amount == 0 || p.cash < amount as i64 {
        return Err("LEDGER_NO_MONEY".to_string());
    }
    for b in ctx.db.bid().tunnus().filter(&tunnus).collect::<Vec<_>>() {
        if b.status == 0 && b.bidder_id == p.id {
            ctx.db.bid().id().update(Bid { status: 3, ..b });
        }
    }
    ctx.db.bid().insert(Bid {
        id: 0,
        tunnus: tunnus.clone(),
        bidder_id: p.id,
        bidder_name: p.name.clone(),
        amount,
        placed_month: t.month,
        expires_month: t.month + BID_LIFE_MONTHS,
        status: 0,
    });
    push_event(ctx, t.month, "bid", format!("{} bid {} € on {}", p.name, amount, par.address), "", "", &tunnus, p.id, amount as i64, "");
    Ok(())
}

#[reducer]
pub fn withdraw_bid(ctx: &ReducerContext, bid_id: u64) -> Result<(), String> {
    let p = me(ctx)?;
    let b = ctx.db.bid().id().find(bid_id).ok_or_else(|| "LEDGER_NO_BID".to_string())?;
    if b.bidder_id != p.id || b.status != 0 {
        return Err("LEDGER_NO_BID".to_string());
    }
    ctx.db.bid().id().update(Bid { status: 3, ..b });
    Ok(())
}

#[reducer]
pub fn accept_bid(ctx: &ReducerContext, bid_id: u64) -> Result<(), String> {
    let t = town(ctx)?;
    let p = me(ctx)?;
    let b = ctx.db.bid().id().find(bid_id).ok_or_else(|| "LEDGER_NO_BID".to_string())?;
    let par = parcel(ctx, &b.tunnus)?;
    if par.owner_id != p.id {
        return Err("LEDGER_NOT_OWNER".to_string());
    }
    if b.status != 0 {
        return Err("LEDGER_NO_BID".to_string());
    }
    let amount = b.amount;
    ctx.db.bid().id().update(Bid { status: 1, ..b.clone() });
    if b.bidder_id == 0 {
        // an AI family pays from nowhere; the parcel returns to the market as an original-owner plot
        let mut par = par;
        par.owner_id = 0;
        par.owner_name = b.bidder_name.clone();
        par.for_sale = true;
        par.price = rules::list_price(par.land_value, t.price_index_permille);
        let tunnus = par.tunnus.clone();
        let address = par.address.clone();
        ctx.db.parcel().tunnus().update(par);
        credit(ctx, p.clone(), amount as i64);
        push_event(ctx, t.month, "sale", format!("Sold {} ({}) to the {} family", address, tunnus, b.bidder_name), "", "", &tunnus, p.id, amount as i64, "");
        return Ok(());
    }
    let buyer = player_by_id(ctx, b.bidder_id).ok_or_else(|| "LEDGER_NO_BID".to_string())?;
    if buyer.cash < amount as i64 {
        ctx.db.bid().id().update(Bid { status: 2, ..b });
        return Err("LEDGER_BIDDER_BROKE".to_string());
    }
    let buyer = credit(ctx, buyer, -(amount as i64));
    transfer(ctx, par, &buyer, amount, t.month, "Sold");
    Ok(())
}

#[reducer]
pub fn pay_obligation(ctx: &ReducerContext, obligation_id: u64) -> Result<(), String> {
    let t = town(ctx)?;
    let p = me(ctx)?;
    let o = ctx.db.obligation().id().find(obligation_id).ok_or_else(|| "LEDGER_NO_OBLIGATION".to_string())?;
    if o.player_id != p.id || o.paid {
        return Err("LEDGER_NO_OBLIGATION".to_string());
    }
    if p.cash < o.amount as i64 {
        return Err("LEDGER_NO_MONEY".to_string());
    }
    credit(ctx, p.clone(), -(o.amount as i64));
    let amount = o.amount;
    let tunnus = o.tunnus.clone();
    ctx.db.obligation().id().update(Obligation { paid: true, ..o });
    push_event(ctx, t.month, "tax", format!("Paid {} €", amount), "", "", &tunnus, p.id, -(amount as i64), "");
    Ok(())
}

#[reducer]
pub fn build(ctx: &ReducerContext, tunnus: String, structure_id: String) -> Result<(), String> {
    let t = town(ctx)?;
    let p = me(ctx)?;
    let par = parcel(ctx, &tunnus)?;
    if par.owner_id != p.id {
        return Err("LEDGER_NOT_OWNER".to_string());
    }
    let s = ctx.db.structure().id().find(&structure_id).ok_or_else(|| "LEDGER_NO_STRUCTURE".to_string())?;
    let built: Vec<String> = ctx.db.improvement().tunnus().filter(&tunnus).map(|i| i.structure_id).collect();
    if built.contains(&structure_id) {
        return Err("LEDGER_ALREADY_BUILT".to_string());
    }
    if !s.requires.is_empty() && !built.contains(&s.requires) {
        return Err("LEDGER_REQUIRES".to_string());
    }
    if !s.purposes.is_empty() && !s.purposes.split(',').any(|c| c.trim() == par.purpose) {
        return Err("LEDGER_WRONG_PURPOSE".to_string());
    }
    if p.cash < s.cost as i64 {
        return Err("LEDGER_NO_MONEY".to_string());
    }
    credit(ctx, p.clone(), -(s.cost as i64));
    ctx.db.improvement().insert(Improvement { id: 0, tunnus: tunnus.clone(), structure_id: structure_id.clone(), player_id: p.id, built_month: t.month });
    push_event(ctx, t.month, "build", format!("{} built {} at {}", p.name, structure_id, par.address), "", "", &tunnus, p.id, -(s.cost as i64), "");
    Ok(())
}

// ---------------------------------------------------------------- grey zones

/// Collect a tenant's arrears now. Money in, heat up, reputation down.
#[reducer]
pub fn press_tenant(ctx: &ReducerContext, tunnus: String) -> Result<(), String> {
    let t = town(ctx)?;
    let p = me(ctx)?;
    let par = parcel(ctx, &tunnus)?;
    if par.owner_id != p.id {
        return Err("LEDGER_NOT_OWNER".to_string());
    }
    let mut total = 0u64;
    for ten in ctx.db.tenant().tunnus().filter(&tunnus).collect::<Vec<_>>() {
        total += ten.arrears;
        ctx.db.tenant().id().update(Tenant { arrears: 0, ..ten });
    }
    if total == 0 {
        return Err("LEDGER_NO_ARREARS".to_string());
    }
    let p2 = Player { heat: p.heat + 2, reputation: p.reputation - 1, ..p.clone() };
    ctx.db.player().id().update(p2.clone());
    credit(ctx, p2, total as i64);
    push_event(ctx, t.month, "rent", format!("Collected {} € of arrears at {}", total, par.address), "", "", &tunnus, p.id, total as i64, "");
    Ok(())
}

/// Pay another owner's tenant arrears and earn a favour.
#[reducer]
pub fn buy_arrears(ctx: &ReducerContext, tunnus: String) -> Result<(), String> {
    let t = town(ctx)?;
    let p = me(ctx)?;
    let par = parcel(ctx, &tunnus)?;
    if par.owner_id == p.id {
        return Err("LEDGER_ALREADY_OWNER".to_string());
    }
    let total: u64 = ctx.db.tenant().tunnus().filter(&tunnus).map(|x| x.arrears).sum();
    if total == 0 {
        return Err("LEDGER_NO_ARREARS".to_string());
    }
    if p.cash < total as i64 {
        return Err("LEDGER_NO_MONEY".to_string());
    }
    for ten in ctx.db.tenant().tunnus().filter(&tunnus).collect::<Vec<_>>() {
        ctx.db.tenant().id().update(Tenant { arrears: 0, ..ten });
    }
    let p2 = Player { favours: p.favours + 1, ..p.clone() };
    ctx.db.player().id().update(p2.clone());
    credit(ctx, p2, -(total as i64));
    push_event(ctx, t.month, "rent", format!("{} settled {} € of arrears at {}", p.name, total, par.address), "", "", &tunnus, p.id, -(total as i64), "");
    Ok(())
}

#[reducer]
pub fn donate(ctx: &ReducerContext, amount: u64) -> Result<(), String> {
    let t = town(ctx)?;
    let p = me(ctx)?;
    if amount == 0 || p.cash < amount as i64 {
        return Err("LEDGER_NO_MONEY".to_string());
    }
    let p2 = Player { reputation: p.reputation + (amount / 1000) as i32, heat: (p.heat - 1).max(0), ..p.clone() };
    ctx.db.player().id().update(p2.clone());
    credit(ctx, p2, -(amount as i64));
    push_event(ctx, t.month, "tax", format!("{} donated {} € to the town", p.name, amount), "", "", "", p.id, -(amount as i64), "");
    Ok(())
}

#[reducer]
pub fn grant_cash(ctx: &ReducerContext, amount: i64) -> Result<(), String> {
    let t = town(ctx)?;
    if !t.debug {
        return Err("LEDGER_NOT_DEBUG".to_string());
    }
    let p = me(ctx)?;
    credit(ctx, p, amount);
    Ok(())
}

// ---------------------------------------------------------------- the month tick

#[reducer]
pub fn tick(ctx: &ReducerContext, _s: TickSchedule) -> Result<(), String> {
    if ctx.sender() != ctx.database_identity() {
        return Err("LEDGER_NOT_SCHEDULER".to_string());
    }
    let t = match ctx.db.town().id().find(0) {
        Some(t) if t.seeded => t,
        _ => return Ok(()),
    };
    // stale presence rows go first; a town with nobody in it sleeps
    let now = ctx.timestamp.to_micros_since_unix_epoch();
    for pr in ctx.db.presence().iter().collect::<Vec<_>>() {
        if now - pr.updated.to_micros_since_unix_epoch() > PRESENCE_STALE_MICROS {
            ctx.db.presence().player_id().delete(pr.player_id);
        }
    }
    if ctx.db.presence().count() == 0 {
        return Ok(());
    }
    let cfg = config(ctx)?;
    let month = t.month + 1;
    let mut rng = ctx.rng();

    // rents and tenant arrears
    for par in ctx.db.parcel().iter().filter(|p| p.owner_id != 0).collect::<Vec<_>>() {
        let owner = match player_by_id(ctx, par.owner_id) {
            Some(o) => o,
            None => continue,
        };
        let bonus: u64 = ctx.db.improvement().tunnus().filter(&par.tunnus).filter_map(|i| ctx.db.structure().id().find(&i.structure_id)).map(|s| s.rent_bonus).sum();
        let tenants: Vec<Tenant> = ctx.db.tenant().tunnus().filter(&par.tunnus).collect();
        let factors: Vec<u32> = tenants.iter().map(|t| rules::tenant_factor_permille(t.turnover, &t.health)).collect();
        let base = rules::rent_with_tenants(par.rent_month + bonus, &factors);
        let mut paid = 0u64;
        if tenants.is_empty() {
            paid = base;
        } else {
            let n = tenants.len() as u64;
            let share = base / n;
            for (k, ten) in tenants.into_iter().enumerate() {
                // the last tenant carries the remainder so the parcel pays exactly its yield
                let part = if (k as u64) < n - 1 { share } else { base - share * (n - 1) };
                let chance = if ten.status == "R" { cfg.arrears_chance_permille } else { cfg.arrears_chance_bad_status_permille };
                if rng.gen_range(0..1000u32) < chance {
                    ctx.db.tenant().id().update(Tenant { arrears: ten.arrears + part, ..ten });
                } else {
                    paid += part;
                }
            }
        }
        if paid > 0 {
            credit(ctx, owner.clone(), paid as i64);
            push_event(ctx, month, "rent", format!("Rent {} € from {}", paid, par.address), "", "", &par.tunnus, owner.id, paid as i64, "");
        }
        let tax = rules::tax_month(par.land_value, cfg.tax_rate_year_permille);
        if tax > 0 {
            ctx.db.obligation().insert(Obligation { id: 0, player_id: owner.id, kind: "land_tax".to_string(), tunnus: par.tunnus.clone(), amount: tax, due_month: month + 1, paid: false });
        }
    }

    // overdue obligations are collected with a penalty and warm the owner up
    for o in ctx.db.obligation().iter().filter(|o| !o.paid && month > o.due_month + cfg.obligation_grace_months).collect::<Vec<_>>() {
        if let Some(p) = player_by_id(ctx, o.player_id) {
            let total = o.amount + rules::penalty(o.amount, cfg.penalty_permille);
            let p2 = Player { heat: p.heat + 1, ..p };
            ctx.db.player().id().update(p2.clone());
            credit(ctx, p2, -(total as i64));
            ctx.db.obligation().id().update(Obligation { paid: true, ..o.clone() });
            push_event(ctx, month, "tax", format!("Overdue {} collected with penalty: {} €", o.kind, total), "", "", &o.tunnus, o.player_id, -(total as i64), "");
        }
    }

    // prices drift; unowned parcels follow the index
    let index = rules::drift_index(t.price_index_permille, cfg.drift_permille, rng.gen_range(0..1000u32));
    for par in ctx.db.parcel().iter().filter(|p| p.owner_id == 0).collect::<Vec<_>>() {
        let price = rules::list_price(par.land_value, index);
        ctx.db.parcel().tunnus().update(Parcel { price, ..par });
    }

    // AI families bid on player parcels now and then; stale bids expire
    if !cfg.families.is_empty() && rng.gen_range(0..1000u32) < cfg.ai_bid_chance_permille {
        let owned: Vec<Parcel> = ctx.db.parcel().iter().filter(|p| p.owner_id != 0).collect();
        if !owned.is_empty() {
            let par = &owned[rng.gen_range(0..owned.len())];
            let family = cfg.families[rng.gen_range(0..cfg.families.len())].clone();
            let amount = rules::family_bid(par.price.max(par.land_value), rng.gen_range(0..300u32));
            ctx.db.bid().insert(Bid { id: 0, tunnus: par.tunnus.clone(), bidder_id: 0, bidder_name: family.clone(), amount, placed_month: month, expires_month: month + BID_LIFE_MONTHS, status: 0 });
            push_event(ctx, month, "bid", format!("The {} family offers {} € for {}", family, amount, par.address), "", "", &par.tunnus, 0, amount as i64, "");
        }
    }
    for b in ctx.db.bid().iter().filter(|b| b.status == 0 && b.expires_month <= month).collect::<Vec<_>>() {
        ctx.db.bid().id().update(Bid { status: 4, ..b });
    }

    ctx.db.town().id().update(Town { month, price_index_permille: index, ..t });
    push_event(ctx, month, "tick", format!("Month {}", month), "", "", "", 0, 0, "");
    prune_events(ctx);
    Ok(())
}
