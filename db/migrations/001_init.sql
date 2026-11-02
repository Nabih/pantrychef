-- Core read model for PantryChef.
-- Facts only: names, ingredient lines, nutrition, times. No recipe
-- instructions or photography from the source, by design.

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE categories (
    id   smallint PRIMARY KEY,
    name text NOT NULL UNIQUE
);

CREATE TABLE ingredients (
    id           integer PRIMARY KEY,
    key          text NOT NULL UNIQUE,
    display      text NOT NULL,
    group_id     smallint NOT NULL,
    recipe_count integer NOT NULL,
    is_staple    boolean NOT NULL DEFAULT false
);

CREATE INDEX ingredients_display_trgm_idx ON ingredients USING gin (display gin_trgm_ops);
CREATE INDEX ingredients_popularity_idx ON ingredients (recipe_count DESC, id);

CREATE TABLE recipes (
    id            integer PRIMARY KEY,
    name          text NOT NULL,
    minutes       smallint NOT NULL DEFAULT 0,
    calories      integer,
    servings      smallint,
    category_id   smallint REFERENCES categories (id),
    n_ingredients smallint NOT NULL,
    foodcom_id    integer,
    source_url    text NOT NULL
);

CREATE INDEX recipes_name_trgm_idx ON recipes USING gin (name gin_trgm_ops);
CREATE INDEX recipes_minutes_idx ON recipes (minutes);
CREATE INDEX recipes_category_idx ON recipes (category_id);
CREATE INDEX recipes_foodcom_idx ON recipes (foodcom_id) WHERE foodcom_id IS NOT NULL;

-- Doubles as the inverted index used for matching.
CREATE TABLE recipe_ingredients (
    recipe_id     integer NOT NULL REFERENCES recipes (id) ON DELETE CASCADE,
    ingredient_id integer NOT NULL REFERENCES ingredients (id),
    line          text NOT NULL,
    position      smallint NOT NULL,
    PRIMARY KEY (recipe_id, ingredient_id)
);

CREATE INDEX recipe_ingredients_lookup_idx
    ON recipe_ingredients (ingredient_id, recipe_id);
