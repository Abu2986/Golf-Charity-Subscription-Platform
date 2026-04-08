-- =====================================================
-- GreenHeart Platform — Supabase Database Schema
-- =====================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─────────────────────────────────────────
-- USERS (extends Supabase auth.users)
-- ─────────────────────────────────────────
CREATE TABLE public.profiles (
  id               UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  first_name       TEXT NOT NULL,
  last_name        TEXT NOT NULL,
  email            TEXT NOT NULL UNIQUE,
  avatar_url       TEXT,
  role             TEXT NOT NULL DEFAULT 'subscriber' CHECK (role IN ('subscriber','admin')),
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at       TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────
-- SUBSCRIPTIONS
-- ─────────────────────────────────────────
CREATE TABLE public.subscriptions (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id               UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  plan                  TEXT NOT NULL CHECK (plan IN ('monthly','yearly')),
  status                TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','cancelled','lapsed','trialing')),
  stripe_customer_id    TEXT UNIQUE,
  stripe_subscription_id TEXT UNIQUE,
  stripe_price_id       TEXT,
  current_period_start  TIMESTAMPTZ,
  current_period_end    TIMESTAMPTZ,
  cancel_at_period_end  BOOLEAN DEFAULT FALSE,
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────
-- CHARITIES
-- ─────────────────────────────────────────
CREATE TABLE public.charities (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name            TEXT NOT NULL,
  slug            TEXT NOT NULL UNIQUE,
  category        TEXT NOT NULL CHECK (category IN ('health','children','environment','sport','mental','education','other')),
  description     TEXT,
  long_description TEXT,
  logo_url        TEXT,
  banner_url      TEXT,
  website_url     TEXT,
  is_featured     BOOLEAN DEFAULT FALSE,
  is_active       BOOLEAN DEFAULT TRUE,
  upcoming_events JSONB DEFAULT '[]',
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────
-- USER CHARITY SELECTIONS
-- ─────────────────────────────────────────
CREATE TABLE public.user_charities (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id               UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  charity_id            UUID NOT NULL REFERENCES public.charities(id),
  contribution_pct      DECIMAL(5,2) NOT NULL DEFAULT 10.00
                        CHECK (contribution_pct >= 10.00 AND contribution_pct <= 100.00),
  is_active             BOOLEAN DEFAULT TRUE,
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, is_active) -- only one active charity per user
);

-- ─────────────────────────────────────────
-- GOLF SCORES
-- ─────────────────────────────────────────
CREATE TABLE public.golf_scores (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  score       INTEGER NOT NULL CHECK (score >= 1 AND score <= 45),
  played_date DATE NOT NULL,
  is_active   BOOLEAN DEFAULT TRUE, -- false = replaced by newer score
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────
-- DRAWS
-- ─────────────────────────────────────────
CREATE TABLE public.draws (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  draw_month      DATE NOT NULL UNIQUE, -- first day of the draw month
  logic_type      TEXT NOT NULL DEFAULT 'random' CHECK (logic_type IN ('random','algorithmic')),
  drawn_numbers   INTEGER[5],           -- the 5 winning numbers
  status          TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','simulated','published','completed')),
  jackpot_amount  DECIMAL(10,2) DEFAULT 0,
  pool_4match     DECIMAL(10,2) DEFAULT 0,
  pool_3match     DECIMAL(10,2) DEFAULT 0,
  total_pool      DECIMAL(10,2) DEFAULT 0,
  jackpot_rolled  BOOLEAN DEFAULT FALSE,
  simulation_data JSONB,
  published_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────
-- DRAW ENTRIES (user participation per draw)
-- ─────────────────────────────────────────
CREATE TABLE public.draw_entries (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  draw_id       UUID NOT NULL REFERENCES public.draws(id),
  user_id       UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  score_snapshot INTEGER[] NOT NULL, -- snapshot of user's 5 scores at draw time
  match_count   INTEGER CHECK (match_count >= 0 AND match_count <= 5),
  is_winner     BOOLEAN DEFAULT FALSE,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (draw_id, user_id)
);

-- ─────────────────────────────────────────
-- WINNINGS
-- ─────────────────────────────────────────
CREATE TABLE public.winnings (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  draw_entry_id   UUID NOT NULL REFERENCES public.draw_entries(id),
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  draw_id         UUID NOT NULL REFERENCES public.draws(id),
  match_type      TEXT NOT NULL CHECK (match_type IN ('5_match','4_match','3_match')),
  amount          DECIMAL(10,2) NOT NULL,
  status          TEXT NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','proof_submitted','approved','rejected','paid')),
  proof_url       TEXT,
  proof_submitted_at TIMESTAMPTZ,
  verified_by     UUID REFERENCES public.profiles(id),
  verified_at     TIMESTAMPTZ,
  paid_at         TIMESTAMPTZ,
  notes           TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────
-- CHARITY CONTRIBUTIONS (audit trail)
-- ─────────────────────────────────────────
CREATE TABLE public.charity_contributions (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  charity_id      UUID NOT NULL REFERENCES public.charities(id),
  subscription_id UUID REFERENCES public.subscriptions(id),
  amount          DECIMAL(10,2) NOT NULL,
  contribution_pct DECIMAL(5,2) NOT NULL,
  period_start    TIMESTAMPTZ,
  period_end      TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────
-- PRIZE POOL CONFIG
-- ─────────────────────────────────────────
CREATE TABLE public.prize_pool_config (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  plan_monthly_price  DECIMAL(10,2) NOT NULL DEFAULT 9.99,
  plan_yearly_price   DECIMAL(10,2) NOT NULL DEFAULT 95.88,
  pool_pct_of_sub     DECIMAL(5,2) NOT NULL DEFAULT 70.00, -- % of subscription going to pool
  charity_min_pct     DECIMAL(5,2) NOT NULL DEFAULT 10.00,
  match5_pool_share   DECIMAL(5,2) NOT NULL DEFAULT 40.00,
  match4_pool_share   DECIMAL(5,2) NOT NULL DEFAULT 35.00,
  match3_pool_share   DECIMAL(5,2) NOT NULL DEFAULT 25.00,
  is_active           BOOLEAN DEFAULT TRUE,
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

-- Insert default config
INSERT INTO public.prize_pool_config (plan_monthly_price, plan_yearly_price, pool_pct_of_sub, charity_min_pct, match5_pool_share, match4_pool_share, match3_pool_share)
VALUES (9.99, 95.88, 70.00, 10.00, 40.00, 35.00, 25.00);

-- ─────────────────────────────────────────
-- VIEWS
-- ─────────────────────────────────────────

-- Active subscribers with their current charity
CREATE VIEW public.active_subscribers AS
SELECT 
  p.id,
  p.first_name,
  p.last_name,
  p.email,
  s.plan,
  s.status,
  s.current_period_end,
  c.name AS charity_name,
  uc.contribution_pct
FROM public.profiles p
JOIN public.subscriptions s ON s.user_id = p.id AND s.status = 'active'
LEFT JOIN public.user_charities uc ON uc.user_id = p.id AND uc.is_active = TRUE
LEFT JOIN public.charities c ON c.id = uc.charity_id;

-- User's 5 most recent active scores
CREATE VIEW public.user_active_scores AS
SELECT DISTINCT ON (user_id)
  user_id,
  array_agg(score ORDER BY played_date DESC) FILTER (WHERE rn <= 5) AS scores
FROM (
  SELECT 
    user_id,
    score,
    played_date,
    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY played_date DESC) AS rn
  FROM public.golf_scores
  WHERE is_active = TRUE
) ranked
GROUP BY user_id;

-- Monthly charity totals
CREATE VIEW public.charity_monthly_totals AS
SELECT 
  c.id,
  c.name,
  c.category,
  SUM(cc.amount) AS total_raised,
  COUNT(DISTINCT cc.user_id) AS supporter_count,
  DATE_TRUNC('month', cc.created_at) AS month
FROM public.charities c
LEFT JOIN public.charity_contributions cc ON cc.charity_id = c.id
GROUP BY c.id, c.name, c.category, DATE_TRUNC('month', cc.created_at);

-- ─────────────────────────────────────────
-- FUNCTIONS
-- ─────────────────────────────────────────

-- Function: enforce max 5 scores per user (remove oldest when 6th added)
CREATE OR REPLACE FUNCTION enforce_score_limit()
RETURNS TRIGGER AS $$
BEGIN
  -- Count current active scores
  IF (SELECT COUNT(*) FROM public.golf_scores WHERE user_id = NEW.user_id AND is_active = TRUE) >= 5 THEN
    -- Deactivate the oldest score
    UPDATE public.golf_scores
    SET is_active = FALSE
    WHERE id = (
      SELECT id FROM public.golf_scores
      WHERE user_id = NEW.user_id AND is_active = TRUE
      ORDER BY played_date ASC, created_at ASC
      LIMIT 1
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_score_limit
BEFORE INSERT ON public.golf_scores
FOR EACH ROW EXECUTE FUNCTION enforce_score_limit();

-- Function: calculate prize pool for a draw
CREATE OR REPLACE FUNCTION calculate_prize_pool(draw_month_date DATE)
RETURNS TABLE(total DECIMAL, jackpot DECIMAL, pool_4 DECIMAL, pool_3 DECIMAL) AS $$
DECLARE
  active_count INTEGER;
  monthly_price DECIMAL;
  pool_pct DECIMAL;
  config RECORD;
BEGIN
  SELECT * INTO config FROM public.prize_pool_config WHERE is_active = TRUE LIMIT 1;
  
  SELECT COUNT(*) INTO active_count
  FROM public.subscriptions
  WHERE status = 'active';
  
  -- Simplified: use monthly price for all subscribers
  total := active_count * config.plan_monthly_price * (config.pool_pct_of_sub / 100);
  jackpot := total * (config.match5_pool_share / 100);
  pool_4 := total * (config.match4_pool_share / 100);
  pool_3 := total * (config.match3_pool_share / 100);
  
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────
-- RLS POLICIES
-- ─────────────────────────────────────────
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.golf_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_charities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.draw_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.winnings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.charities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.draws ENABLE ROW LEVEL SECURITY;

-- Users can only see/edit their own data
CREATE POLICY "Users own profile" ON public.profiles
  FOR ALL USING (auth.uid() = id);

CREATE POLICY "Users own subscription" ON public.subscriptions
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users own scores" ON public.golf_scores
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users own charity selection" ON public.user_charities
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users own draw entries" ON public.draw_entries
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users own winnings" ON public.winnings
  FOR SELECT USING (auth.uid() = user_id);

-- Charities and draws are public read
CREATE POLICY "Public charities" ON public.charities
  FOR SELECT USING (is_active = TRUE);

CREATE POLICY "Public draws" ON public.draws
  FOR SELECT USING (status = 'published' OR status = 'completed');

-- Admin full access (based on role in profiles)
CREATE POLICY "Admin all profiles" ON public.profiles
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- ─────────────────────────────────────────
-- INDEXES
-- ─────────────────────────────────────────
CREATE INDEX idx_golf_scores_user_active ON public.golf_scores (user_id, is_active, played_date DESC);
CREATE INDEX idx_subscriptions_user ON public.subscriptions (user_id, status);
CREATE INDEX idx_draw_entries_draw ON public.draw_entries (draw_id, is_winner);
CREATE INDEX idx_winnings_user ON public.winnings (user_id, status);
CREATE INDEX idx_charities_category ON public.charities (category, is_active);
CREATE INDEX idx_charity_contributions_charity ON public.charity_contributions (charity_id, created_at);
