-- Accounts and personalisation scaffolding.
-- Nothing writes to these yet; they exist so favourites and pantry history
-- have a home when the app grows a login.

CREATE TABLE app_user (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email         text UNIQUE,
    display_name  text,
    created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE favorite_recipe (
    user_id    uuid NOT NULL REFERENCES app_user (id) ON DELETE CASCADE,
    recipe_id  integer NOT NULL REFERENCES recipes (id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, recipe_id)
);

CREATE INDEX favorite_recipe_recipe_idx ON favorite_recipe (recipe_id);

CREATE TABLE favorite_ingredient (
    user_id       uuid NOT NULL REFERENCES app_user (id) ON DELETE CASCADE,
    ingredient_id integer NOT NULL REFERENCES ingredients (id) ON DELETE CASCADE,
    created_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, ingredient_id)
);

-- A user's saved pantry, so the app can restore it across devices.
CREATE TABLE pantry_item (
    user_id       uuid NOT NULL REFERENCES app_user (id) ON DELETE CASCADE,
    ingredient_id integer NOT NULL REFERENCES ingredients (id) ON DELETE CASCADE,
    created_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, ingredient_id)
);

-- Interaction log for future recommendations: opens, saves, cooked.
CREATE TABLE recipe_event (
    id         bigserial PRIMARY KEY,
    user_id    uuid REFERENCES app_user (id) ON DELETE SET NULL,
    recipe_id  integer NOT NULL REFERENCES recipes (id) ON DELETE CASCADE,
    kind       text NOT NULL CHECK (kind IN ('view', 'save', 'cook')),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX recipe_event_recipe_idx ON recipe_event (recipe_id, kind);
CREATE INDEX recipe_event_user_idx ON recipe_event (user_id, created_at DESC);
