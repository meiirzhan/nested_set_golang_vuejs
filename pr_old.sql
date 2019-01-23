-- LINK http://zabolotnev.com/mysql-nested-sets
DROP PROCEDURE IF EXISTS rebuild_nested_set_tree$$


-- 0.2 Приведение данных к nested set через parent_id
CREATE PROCEDURE rebuild_nested_set_tree()
BEGIN

    -- Изначально сбрасываем все границы
    UPDATE tree SET level = 0, left_key = 0, right_key = 0;

    -- Устанавливаем границы корневым элементам
    SET @i := 0;
    UPDATE tree SET left_key = (@i := @i + 1), right_key = (@i := @i + 1)
    WHERE parent_id IS NULL;

    SET @parent_id  := NULL;
    SET @parent_right := NULL;

    forever: LOOP

        -- Находим элемент с минимальной правой границей - самый левый в дереве
        SET @parent_id := NULL;

        SELECT t.`id`, t.`right_key` FROM `tree` t, `tree` tc
        WHERE t.`id` = tc.`parent_id` AND tc.`left_key` = 0 AND t.`right_key` <> 0
        ORDER BY t.`right_key`, t.`id` LIMIT 1 INTO @parent_id, @parent_right;

        -- Выходим из бесконечности, когда у нас уже нет незаполненных элементов
        IF @parent_id IS NULL THEN
            LEAVE forever;
        END IF;

        -- Сохраняем левую границу текущего ряда
        SET @current_left := @parent_right;

        -- Вычисляем максимальную правую границу текущего ряда
        SELECT @current_left + COUNT(*) * 2 FROM `tree`
        WHERE `parent_id` = @parent_id INTO @parent_right;

        -- Вычисляем длину текущего ряда
        SET @current_length := @parent_right - @current_left;

        -- Обновляем правые границы всех элементов, которые правее
        UPDATE `tree` SET `right_key` = `right_key` + @current_length
        WHERE `right_key` >= @current_left ORDER BY `right_key`;

        -- Обновляем левые границы всех элементов, которые правее
        UPDATE `tree` SET `left_key` = `left_key` + @current_length
        WHERE `left_key` > @current_left ORDER BY left_key;

        -- И только сейчас обновляем границы текущего ряда
        SET @i := @current_left - 1;
        UPDATE `tree` SET `left_key` = (@i := @i + 1), `right_key` = (@i := @i + 1)
        WHERE `parent_id` = @parent_id ORDER BY `id`;

    END LOOP;

    -- Дальше заполняем поля level

    -- Устанавливаем 1-й уровень всем корневым категориям классификатора
    UPDATE `tree` SET `level` = 1 WHERE `parent_id` IS NULL;

    SET @unprocessed_rows_count = 100500;

    WHILE @unprocessed_rows_count > 0 DO

        UPDATE `tree` top, `tree` bottom SET bottom.`level` = top.`level` + 1
        WHERE bottom.`level` = 0 AND top.`level` <> 0 AND top.`id` = bottom.`parent_id`;

        SELECT COUNT(*) FROM `tree` WHERE `level` = 0 LIMIT 1 INTO @unprocessed_rows_count;

    END WHILE;

END$$


DROP PROCEDURE IF EXISTS create_node$$


-- 0.2 Добавление узла
CREATE PROCEDURE create_node(IN n_parent_id INT(10), IN n_name VARCHAR(155))
BEGIN
	SET @right_key := 1;
	SET @level := 0;
	-- Находим правый ключ
	IF n_parent_id IS NULL THEN
		-- Если узел корневой, то знание right_key максимальное число + 1
		SELECT MAX(right_key) + 1
		INTO @right_key
		FROM tree;
	ELSE
		SELECT right_key, level
		INTO @right_key, @level
		FROM tree 
		WHERE id = n_parent_id
		LIMIT 1;
	END IF;

	IF @right_key IS NULL THEN
		SET @right_key := 1;
	END IF;
	-- Обновляем значние родителей
	UPDATE tree SET right_key = right_key + 2, left_key = IF(left_key > @right_key, left_key + 2, left_key) WHERE right_key >= @right_key;

	-- Добавляем строку
	INSERT INTO tree SET left_key = @right_key, right_key = @right_key + 1, level = @level + 1, name = n_name, parent_id = n_parent_id;
	-- SET n_id = LAST_INSERT_ID();

END$$

DROP PROCEDURE IF EXISTS drop_node$$


-- 0.2 Удаление данных
CREATE PROCEDURE drop_node(IN n_id INT(10))
BEGIN
	SET @left_key := 0;
	SET @right_key := 0;

	-- Находим left_key и right_key по ID
	SELECT left_key, right_key
	INTO @left_key, @right_key
	FROM tree 
	WHERE id = n_id;

	DELETE FROM tree WHERE left_key >= $left_key AND right_ key <= $right_key;

	-- Обновляем ключи оставшихся веток
	UPDATE tree SET left_key = IF(left_key > @left_key, left_key - (@right_key - @left_key + 1), left_key), right_key = right_key - (@right_key - @left_key + 1) WHERE right_key > @right_key;
END$$



DROP PROCEDURE IF EXISTS update_node$$


-- 0.2 Перемещение узла
CREATE PROCEDURE update_node(IN n_id INT(10), IN new_parent_id INT(10), IN next_node_id INT(10))
BEGIN
	SET @level := 0;
	SET @left_key := 0;
	SET @right_key := 0;
	SET @parent_id := 0;

	SET @new_level := 0;
	SET @new_left_key := 1;
	SET @new_right_key := 0;

	-- Получаем данные узла
	SELECT level, left_key, right_key
	INTO @level, @left_key, @right_key
	FROM tree WHERE id = n_id;



	IF new_parent_id IS NULL THEN

		-- Перемещение в корень
		SELECT MAX(right_key)
		INTO @right_key
		FROM tree;

	ELSEIF @parent_id = new_parent_id THEN

		-- Изменение порядка
		SELECT level, left_key, right_key
		INTO @new_level, @new_left_key, @new_right_key
		FROM tree WHERE id = next_node_id;

	ELSEIF new_parent_id <> @parent_id THEN

		-- Простое перемещение
		SELECT level, left_key, right_key - 1
		INTO @new_level, @new_left_key, @new_right_key
		FROM tree WHERE id = new_parent_id;

	END IF;

	SET @skew_level := @new_level - @level + 1;
	SET @skew_tree := @right_key - @left_key + 1;
	SET @skew_edit := @new_right_key - @left_key + 1;

	IF @level <= @new_level THEN
	-- Обновляем узлы
		UPDATE tree 
		SET
		left_key = IF(right_key <= @right_key, left_key + @skew_edit, IF(left_key > @right_key, left_key - @skew_tree, left_key)),
		level = IF(right_key <= @right_key, level + @skew_level, level),
		right_key = IF(right_key <= @right_key, right_key + @skew_edit, IF(right_key <= @new_right_key, right_key - @skew_tree, right_key)) 
		WHERE
		right_key > @left_key AND left_key <= @new_right_key;
	ELSE
		UPDATE my_table 
		SET left_key = IF(right_key <= $right_key, left_key + $skew_edit, IF(left_key > $right_key, left_key - $skew_tree, left_key)), 
		level = IF(right_key <= $right_key, level + $skew_level, level), 
		right_key = IF(right_key <= $right_key, right_key + $skew_edit, IF(right_key <= $right_key_near, right_key - $skew_tree, right_key)) 
		WHERE right_key > $left_key AND left_key <= $right_key_near
	END IF;

END$$




















