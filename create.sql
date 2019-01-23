-- phpMyAdmin SQL Dump
-- version 4.8.2
-- https://www.phpmyadmin.net/
--
-- Host: localhost:3306
-- Generation Time: Jan 23, 2019 at 11:16 AM
-- Server version: 5.7.21
-- PHP Version: 7.1.19

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";

--
-- Database: `nested_set_db`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `create_node` (IN `n_parent_id` INT(10), IN `n_name` VARCHAR(155), IN `n_tree` INT(10), IN `n_left_key` INT(10))  BEGIN
	SET @left_key := 0;
    SET @level := 0;
    IF n_tree IS NULL AND n_parent_id IS NULL THEN
        SELECT MAX(tree) + 1 FROM `_ns_tree` INTO n_tree;
    END IF;
    IF n_tree IS NULL AND n_parent_id IS NOT NULL THEN
        SELECT tree FROM `_ns_tree` WHERE id = n_parent_id INTO n_tree;
    END IF;
-- Если мы указали родителя:
    IF n_parent_id IS NOT NULL AND n_parent_id > 0 THEN
        SELECT right_key, `level` + 1 INTO @left_key, @level
            FROM ns_tree
            WHERE id = n_parent_id AND tree = n_tree;
    END IF;
-- Если мы указали левый ключ:
    IF  n_left_key IS NOT NULL AND n_left_key > 0 AND
        (@left_key IS NULL OR @left_key = 0) THEN
        SELECT id, left_key, right_key, `level`, parent_id
            INTO @tmp_id, @tmp_left_key, @tmp_right_key, @tmp_level, @tmp_parent_id
            FROM ns_tree
            WHERE tree = n_tree AND (left_key = n_left_key OR right_key = n_left_key);
        IF @tmp_left_key IS NOT NULL AND @tmp_left_key > 0 AND n_left_key = @tmp_left_key THEN
            SET n_parent_id := @tmp_parent_id;
            SET @left_key := n_left_key;
            SET @level := @tmp_level;
        ELSEIF @tmp_left_key IS NOT NULL AND @tmp_left_key > 0 AND n_left_key = @tmp_right_key THEN
            SET n_parent_id := @tmp_id;
            SET @left_key := n_left_key;
            SET @level := @tmp_level + 1;
        END IF;
    END IF;
-- Если родитель или левый ключ не указан, или мы ничего не нашли
    IF @left_key IS NULL OR @left_key = 0 THEN
        SELECT MAX(right_key) + 1 INTO @left_key
            FROM ns_tree
            WHERE tree = n_tree;
        IF @left_key IS NULL OR @left_key = 0 THEN
            SET @left_key := 1;
        END IF;
        SET @level := 0;
        SET n_parent_id := 0;
    END IF;
-- Устанавливаем новые значения ключей
    SET n_left_key := @left_key;
    SET @n_right_key := @left_key + 1;
    SET @n_level := @level;
-- Формируем разрыв в дереве
    UPDATE _ns_tree
        SET left_key = CASE WHEN left_key >= @left_key
              THEN left_key + 2
              ELSE left_key + 0
            END,
            right_key = right_key + 2
        WHERE tree = n_tree AND right_key >= @left_key;

    INSERT INTO _ns_tree SET left_key = n_left_key, right_key = @n_right_key, level = @n_level, name = n_name, parent_id = n_parent_id, tree = n_tree;
    -- INSERT INTO ns_tree SET left_key = @right_key, right_key = @right_key + 1, level = @level + 1, name = n_name, parent_id = n_parent_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `drop_node` (IN `n_id` INT(10))  BEGIN

    SET @old_tree := 1;
    SET @old_right_key := 1;
    SET @old_level := 1;
    SET @old_parent_id := 1;
    SET @old_left_key := 1;
    SELECT tree, right_key, level, parent_id, left_key
    INTO @old_tree, @old_right_key, @old_level, @old_parent_id, @old_left_key
    FROM ns_tree WHERE id = n_id;

	DELETE FROM _ns_tree
        WHERE
            tree = @old_tree AND
            left_key > @old_left_key AND
            right_key < @old_right_key;
-- Убираем разрыв в ключах:
    SET @skew_tree := @old_right_key - @old_left_key + 1;
    UPDATE _ns_tree
        SET left_key = CASE WHEN left_key > @old_left_key
                            THEN left_key - @skew_tree
                            ELSE left_key
                       END,
            right_key = right_key - @skew_tree
        WHERE right_key > @old_right_key AND
            tree = @old_tree AND
            id <> n_id;
    DELETE FROM _ns_tree WHERE id = n_id;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `rebuild_nested_set_tree` ()  BEGIN

    -- Изначально сбрасываем все границы
    UPDATE _ns_tree SET level = 0, left_key = 0, right_key = 0;

    -- Устанавливаем границы корневым элементам
    SET @i := 0;
    UPDATE _ns_tree SET left_key = 1, right_key = 2
    WHERE parent_id = 0;

    SET @parent_id  := NULL;
    SET @parent_right := NULL;
    SET @tree := NULL;
    SET @level := NULL;
    SET @j := 0;
    forever: LOOP

        -- Находим элемент с минимальной правой границей - самый левый в дереве
        SET @parent_id := NULL;

        SELECT t.`id`, t.`right_key`, t.`tree`, t.`level` FROM `_ns_tree` t, `_ns_tree` tc
        WHERE t.`id` = tc.`parent_id` AND tc.`left_key` = 0 AND t.`right_key` <> 0
        ORDER BY t.`right_key`, t.`id` LIMIT 1 INTO @parent_id, @parent_right, @tree, @level;

        -- Выходим из бесконечности, когда у нас уже нет незаполненных элементов
        IF @parent_id IS NULL THEN
            LEAVE forever;
        END IF;
        -- Сохраняем левую границу текущего ряда
        SET @current_left := @parent_right;

        -- Вычисляем максимальную правую границу текущего ряда
        SELECT @current_left + COUNT(*) * 2 FROM `_ns_tree`
        WHERE `parent_id` = @parent_id INTO @parent_right;

        -- Вычисляем длину текущего ряда
        SET @current_length := @parent_right - @current_left;

        -- Обновляем правые границы всех элементов, которые правее
        UPDATE `_ns_tree` SET `right_key` = `right_key` + @current_length
        WHERE `right_key` >= @current_left AND  tree = @tree ORDER BY `right_key`;

        -- Обновляем левые границы всех элементов, которые правее
        UPDATE `_ns_tree` SET `left_key` = `left_key` + @current_length
        WHERE `left_key` > @current_left AND  tree = @tree ORDER BY left_key;

        -- И только сейчас обновляем границы текущего ряда
        SET @i := @current_left - 1;
        UPDATE `_ns_tree` SET `left_key` = (@i := @i + 1), `right_key` = (@i := @i + 1)
        WHERE `parent_id` = @parent_id AND tree = @tree ORDER BY `id`;

    END LOOP;

    -- Дальше заполняем поля level

    -- Устанавливаем 1-й уровень всем корневым категориям классификатора
    UPDATE `_ns_tree` SET `level` = 0 WHERE `parent_id` = 0;

    SET @unprocessed_rows_count = 1000;

    SET @root_count := 0;
    SELECT count(*) FROM `_ns_tree` WHERE parent_id = 0 INTO @root_count;

    WHILE @unprocessed_rows_count > @root_count DO

        UPDATE `_ns_tree` top, `_ns_tree` bottom SET bottom.`level` = top.`level` + 1
        WHERE bottom.`level` = 0 AND top.`id` = bottom.`parent_id`;

        SELECT COUNT(*) FROM `_ns_tree` WHERE `level` = 0 LIMIT 1 INTO @unprocessed_rows_count;

    END WHILE;

END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `update_node` (IN `n_id` INT(10), IN `new_parent_id` INT(10), IN `n_left_key` INT(10))  BEGIN

  SET @old_left_key := 0;
  SET @old_right_key := 0;
  SET @old_level := 0;
  SET @old_tree := 0;
  SET @old_parent_id := 0;
  SELECT left_key, right_key, level, parent_id, tree
  FROM `_ns_tree` WHERE id = n_id LIMIT 1
  INTO @old_left_key, @old_right_key, @old_level, @old_parent_id, @old_tree;

  SET @new_tree := @old_tree;
  SET @new_right_key := @old_right_key;
  SET @new_level := @old_level;
  SET @return_flag := 0;

  SET @new_left_key = n_left_key;


  IF new_parent_id IS NULL THEN SET new_parent_id := 0; END IF;
-- Проверяем, а есть ли изменения связанные со структурой дерева
  IF new_parent_id <> @old_parent_id OR @new_left_key <> @old_left_key THEN
-- Дерево таки перестраиваем, что ж, приступим:
      SET @left_key := 0;
      SET @level := 0;
      SET @skew_tree := @old_right_key - @old_left_key + 1;
-- Определяем куда мы его переносим:
-- Если сменен parent_id:
      IF new_parent_id <> @old_parent_id THEN
-- Если в подчинение другому злу:
          IF new_parent_id > 0 THEN
              SELECT right_key, level + 1
                  INTO @left_key, @level
                  FROM ns_tree
                  WHERE id = new_parent_id AND tree = @new_tree;
-- Иначе в корень дерева переносим:
          ELSE
              SELECT MAX(right_key) + 1
                  INTO @left_key
                  FROM ns_tree
                  WHERE tree = @new_tree;
              SET @level := 0;
          END IF;
-- Если вдруг родитель в диапазоне перемещаемого узла, проверка:
          IF @left_key IS NOT NULL AND
             @left_key > 0 AND
             @left_key > @old_left_key AND
             @left_key <= @old_right_key THEN
                 SET new_parent_id := @old_parent_id;
                 SET @new_left_key := @old_left_key;
                 SET @return_flag := 1;
          END IF;
      END IF;
-- Если не parent_id, то изменен left_key, или если изменение parent_id ничего не дало
      IF @left_key IS NULL OR @left_key = 0 THEN
          SELECT id, left_key, right_key, `level`, parent_id
              INTO @tmp_id, @tmp_left_key, @tmp_right_key, @tmp_level, @tmp_parent_id
              FROM ns_tree
              WHERE tree = @new_tree AND (right_key = @new_left_key OR right_key = @new_left_key - 1)
              LIMIT 1;
          IF @tmp_left_key IS NOT NULL AND
             @tmp_left_key > 0 AND
             @new_left_key - 1 = @tmp_right_key THEN
              SET new_parent_id := @tmp_parent_id;
              SET @left_key := @new_left_key;
              SET @level := @tmp_level;
          ELSEIF @tmp_left_key IS NOT NULL AND
                 @tmp_left_key > 0 AND
                 @new_left_key = @tmp_right_key THEN
              SET new_parent_id := @tmp_id;
              SET @left_key := @new_left_key;
              SET @level := @tmp_level + 1;
          ELSEIF @new_left_key = 1 THEN
              SET new_parent_id := 0;
              SET @left_key := @new_left_key;
              SET @level := 0;
          ELSE
              SET new_parent_id := @old_parent_id;
              SET @new_left_key := @old_left_key;
              SET @return_flag = 1;
          END IF;
      END IF;
-- Теперь мы знаем куда мы перемещаем дерево
-- Проверяем а стоит ли это делать
      IF @return_flag IS NULL OR @return_flag = 0 THEN
          SET @skew_level := @level - @old_level;
          IF @left_key > @old_left_key THEN
-- Перемещение вверх по дереву
              SET @skew_edit := @left_key - @old_left_key - @skew_tree;
              UPDATE _ns_tree
                  SET left_key = CASE WHEN right_key <= @old_right_key
                                       THEN left_key + @skew_edit
                                       ELSE CASE WHEN left_key > @old_right_key
                                                 THEN left_key - @skew_tree
                                                 ELSE left_key
                                            END
                                 END,
                      `level` =  CASE WHEN right_key <= @old_right_key
                                      THEN `level` + @skew_level
                                      ELSE `level`
                                 END,
                      right_key = CASE WHEN right_key <= @old_right_key
                                       THEN right_key + @skew_edit
                                       ELSE CASE WHEN right_key < @left_key
                                                 THEN right_key - @skew_tree
                                                 ELSE right_key
                                            END
                                  END
                  WHERE tree = @old_tree AND
                        right_key > @old_left_key AND
                        left_key < @left_key AND
                        id <> n_id;
              SET @left_key := @left_key - @skew_tree;
          ELSE
-- Перемещение вниз по дереву:
              SET @skew_edit := @left_key - @old_left_key;
              UPDATE _ns_tree
                  SET
                      right_key = CASE WHEN left_key >= @old_left_key
                                       THEN right_key + @skew_edit
                                       ELSE CASE WHEN right_key < @old_left_key
                                                 THEN right_key + @skew_tree
                                                 ELSE right_key
                                            END
                                  END,
                      `level` =   CASE WHEN left_key >= @old_left_key
                                       THEN `level` + @skew_level
                                       ELSE `level`
                                  END,
                      left_key =  CASE WHEN left_key >= @old_left_key
                                       THEN left_key + @skew_edit
                                       ELSE CASE WHEN left_key >= @left_key
                                                 THEN left_key + @skew_tree
                                                 ELSE left_key
                                            END
                                  END
                  WHERE tree = @old_tree AND
                        right_key >= @left_key AND
                        left_key < @old_right_key AND
                        id <> n_id;
          END IF;
-- Дерево перестроили, остался только наш текущий узел
          SET @new_left_key := @left_key;
          SET @new_level := @level;
          SET @new_right_key := @left_key + @skew_tree - 1;
      END IF;
  END IF;
    UPDATE _ns_tree SET parent_id = new_parent_id, right_key = @new_right_key, left_key = @new_left_key, tree = @new_tree, level = @new_level WHERE id = n_id;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `ns_tree`
--

CREATE TABLE `ns_tree` (
  `id` int(11) NOT NULL,
  `left_key` int(11) NOT NULL DEFAULT '0',
  `right_key` int(11) NOT NULL DEFAULT '0',
  `level` int(11) NOT NULL DEFAULT '0',
  `parent_id` int(11) NOT NULL DEFAULT '0',
  `tree` int(11) NOT NULL DEFAULT '1',
  `name` text
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

--
-- Dumping data for table `ns_tree`
--

INSERT INTO `ns_tree` (`id`, `left_key`, `right_key`, `level`, `parent_id`, `tree`, `name`) VALUES
(5, 6, 7, 1, 2, 1, '5'),
(7, 1, 2, 0, 0, 0, '21'),
(4, 3, 4, 1, 3, 1, '4'),
(3, 2, 5, 1, 2, 1, '3'),
(6, 1, 2, 0, 0, 0, 'asdasd'),
(2, 1, 8, 0, 0, 1, '1');

-- --------------------------------------------------------

--
-- Table structure for table `_ns_tree`
--

CREATE TABLE `_ns_tree` (
  `id` int(11) NOT NULL,
  `left_key` int(11) NOT NULL DEFAULT '0',
  `right_key` int(11) NOT NULL DEFAULT '0',
  `level` int(11) NOT NULL DEFAULT '0',
  `parent_id` int(11) NOT NULL DEFAULT '0',
  `tree` int(11) NOT NULL DEFAULT '1',
  `name` text
) ENGINE=MRG_MyISAM DEFAULT CHARSET=utf8 INSERT_METHOD=LAST UNION=(`ns_tree`);

--
-- Indexes for dumped tables
--

--
-- Indexes for table `ns_tree`
--
ALTER TABLE `ns_tree`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `_ns_tree`
--
ALTER TABLE `_ns_tree`
  ADD PRIMARY KEY (`id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `ns_tree`
--
ALTER TABLE `ns_tree`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=17;

--
-- AUTO_INCREMENT for table `_ns_tree`
--
ALTER TABLE `_ns_tree`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
