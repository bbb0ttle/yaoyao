const business = @import("core/business.zig");
const Vec2 = business.Vec2;
const random = @import("random.zig");

pub const MAX_LIFESPAN: f32 = 135.0;
pub const MAX_PARTICLE_SIZE: f32 = 12.0;

pub const ParticleOpts = struct {
    immortal: bool = false,
    floating: bool = false,
    beat: bool = false,
    meteor: bool = false,
    size: f32 = MAX_PARTICLE_SIZE,
};

pub const Particle = struct {
    pos: Vec2,
    vel: Vec2,
    acc: Vec2,
    lifespan: f32,
    size: f32,
    age: f32,
    birth_sec: f32,
    alive: bool,
    immortal: bool,
    floating: bool,
    beat: bool,
    meteor: bool,

    fn init(pos: Vec2, birth_sec: f32, opts: ParticleOpts) Particle {
        return Particle{
            .pos = pos.copy(),
            .vel = Vec2{ .x = random.randomRange(-1.0, 1.0), .y = random.randomRange(-1.0, 0.0) },
            .acc = Vec2{ .x = 0.0, .y = 0.08 },
            .lifespan = MAX_LIFESPAN,
            .size = opts.size,
            .age = 0.0,
            .birth_sec = birth_sec,
            .alive = true,
            .immortal = opts.immortal,
            .floating = opts.floating,
            .beat = opts.beat,
            .meteor = opts.meteor,
        };
    }

    pub fn update(self: *Particle, elapsed: f32, dpr: f32) void {
        if (!self.alive) return;
        if (self.meteor) return;
        self.age += 0.2;

        if (!self.immortal and !self.floating) {
            self.vel = self.vel.add(self.acc);
            self.lifespan -= 2.0;
        }

        if (self.floating) {
            self.pos.x += @sin(self.age) / 6.0;
            self.pos.y += @cos(self.age) / 6.0;
        } else {
            self.pos = self.pos.add(self.vel);
        }

        if (self.beat) {
            const real_age = elapsed - self.birth_sec;
            self.size = business.breath(real_age, (MAX_PARTICLE_SIZE - 3.0) * dpr, MAX_PARTICLE_SIZE * dpr);
        }

        if (self.lifespan < 0.0) {
            self.alive = false;
        }
    }

    fn isDead(self: Particle) bool {
        return !self.alive;
    }
};

const PARTICLE_POOL_SIZE: usize = 5000;
pub var particle_pool: [PARTICLE_POOL_SIZE]Particle = undefined;
pub var particle_pool_len: usize = 0;

pub fn allocParticle(pos: Vec2, elapsed: f32, opts: ParticleOpts) *Particle {
    if (particle_pool_len >= PARTICLE_POOL_SIZE) {
        var i: usize = 0;
        while (i < PARTICLE_POOL_SIZE) : (i += 1) {
            if (!particle_pool[i].alive) {
                particle_pool[i] = Particle.init(pos, elapsed, opts);
                return &particle_pool[i];
            }
        }
        particle_pool[0] = Particle.init(pos, elapsed, opts);
        return &particle_pool[0];
    }
    particle_pool[particle_pool_len] = Particle.init(pos, elapsed, opts);
    const p = &particle_pool[particle_pool_len];
    particle_pool_len += 1;
    return p;
}
