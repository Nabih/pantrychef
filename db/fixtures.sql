-- Small deterministic dataset for API tests.
BEGIN;

TRUNCATE recipe_ingredients, recipes, ingredients, categories CASCADE;

INSERT INTO categories (id, name) VALUES
    (0, 'Dinner'),
    (1, 'Dessert');

INSERT INTO ingredients (id, key, display, group_id, recipe_count, is_staple) VALUES
    (1,  'chicken', 'Chicken', 1, 5, false),
    (2,  'garlic',  'Garlic',  0, 5, false),
    (3,  'onion',   'Onion',   0, 5, false),
    (4,  'tomato',  'Tomato',  0, 4, false),
    (5,  'rice',    'Rice',    3, 3, false),
    (6,  'salt',    'Salt',    4, 9, true),
    (7,  'pepper',  'Pepper',  5, 8, true),
    (8,  'butter',  'Butter',  2, 4, false),
    (9,  'flour',   'Flour',   3, 4, false),
    (10, 'egg',     'Egg',     1, 3, false);

INSERT INTO recipes
    (id, name, minutes, calories, servings, category_id, n_ingredients, foodcom_id, source_url) VALUES
    (10, 'Chicken With Rice', 30, 450, 4, 0, 3, 101, 'https://www.food.com/recipe/x-101'),
    (11, 'Garlic Chicken',    25, 380, 2, 0, 2, 102, 'https://www.food.com/recipe/x-102'),
    (12, 'Tomato Rice',       20, 300, 4, 0, 3, NULL, 'https://www.food.com/search/Tomato+Rice'),
    (13, 'Butter Cake',       60, 500, 8, 1, 3, 103, 'https://www.food.com/recipe/x-103'),
    (14, 'Salt Soup',          5,  10, 1, 0, 1, NULL, 'https://www.food.com/search/Salt+Soup');

INSERT INTO recipe_ingredients (recipe_id, ingredient_id, line, position) VALUES
    (10, 1, '2 chicken breasts', 0),
    (10, 5, '1 cup rice',        1),
    (10, 3, '1 onion',           2),
    (10, 6, '1 tsp salt',        3),
    (11, 1, '1 chicken',         0),
    (11, 2, '3 garlic cloves',   1),
    (11, 6, 'salt',              2),
    (12, 5, '1 cup rice',        0),
    (12, 4, '2 tomatoes',        1),
    (12, 3, '1 onion',           2),
    (13, 9, '2 cups flour',      0),
    (13, 8, '1 cup butter',      1),
    (13, 10, '3 eggs',           2),
    (14, 6, '1 tsp salt',        0);

COMMIT;
