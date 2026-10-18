CREATE TABLE IF NOT EXISTS `vanilla_character_talent` (
  `guid` INT UNSIGNED NOT NULL,
  `talentId` INT UNSIGNED NOT NULL,
  `rank` TINYINT UNSIGNED NOT NULL,
  PRIMARY KEY (`guid`,`talentId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `tbc_character_talent` LIKE `vanilla_character_talent`;
