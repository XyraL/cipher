-- Cipher / Gang Ops schema
-- Import once into your server database.

CREATE TABLE IF NOT EXISTS `cipher_gangs` (
    `id`            INT             NOT NULL AUTO_INCREMENT,
    `name`          VARCHAR(64)     NOT NULL,
    `label`         VARCHAR(64)     NOT NULL,
    `owner`         VARCHAR(64)     NOT NULL,            -- citizenid of boss
    `notoriety`     INT             NOT NULL DEFAULT 0,
    `bank`          BIGINT          NOT NULL DEFAULT 0,
    `dues_amount`   INT             NOT NULL DEFAULT 0,
    `dues_last`     BIGINT          NOT NULL DEFAULT 0,  -- unix ms of last cycle
    `last_active`   BIGINT          NOT NULL DEFAULT 0,  -- unix ms, drives decay
    `created_at`    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cipher_gang_ranks` (
    `gang_id`       INT             NOT NULL,
    `grade`         INT             NOT NULL,
    `name`          VARCHAR(48)     NOT NULL,
    `permissions`   LONGTEXT        NOT NULL,            -- json array or "*"
    PRIMARY KEY (`gang_id`, `grade`),
    CONSTRAINT `fk_ranks_gang` FOREIGN KEY (`gang_id`)
        REFERENCES `cipher_gangs` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cipher_gang_members` (
    `gang_id`       INT             NOT NULL,
    `citizenid`     VARCHAR(64)     NOT NULL,
    `name`          VARCHAR(96)     NOT NULL,            -- cached display name
    `grade`         INT             NOT NULL DEFAULT 0,
    `rep`           INT             NOT NULL DEFAULT 0,  -- personal rep, feeds gang notoriety
    `dues_paid_at`  BIGINT          NOT NULL DEFAULT 0,  -- unix ms of last dues charge, drives offline catch-up
    `joined_at`     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`),                           -- one gang per character
    KEY `idx_gang` (`gang_id`),
    CONSTRAINT `fk_member_gang` FOREIGN KEY (`gang_id`)
        REFERENCES `cipher_gangs` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cipher_task_cooldowns` (
    `citizenid`     VARCHAR(64)     NOT NULL,
    `task_id`       VARCHAR(48)     NOT NULL,
    `completed_at`  BIGINT          NOT NULL DEFAULT 0,  -- unix ms
    PRIMARY KEY (`citizenid`, `task_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Zones are admin-assigned only — there is no in-world capture. A zone may
-- be seeded from Config.Territories, or created entirely from the admin
-- tablet (which also sets coords from the admin's current position).
CREATE TABLE IF NOT EXISTS `cipher_territories` (
    `zone`          VARCHAR(48)     NOT NULL,
    `label`         VARCHAR(64)     NOT NULL DEFAULT '',
    `color`         INT             NOT NULL DEFAULT 0,
    `income`        INT             NOT NULL DEFAULT 0,
    `coord_x`       FLOAT           NULL,
    `coord_y`       FLOAT           NULL,
    `coord_z`       FLOAT           NULL,
    `gang_id`       INT             NULL,                -- assigned gang, null = unassigned
    `assigned_at`   BIGINT          NOT NULL DEFAULT 0,
    PRIMARY KEY (`zone`),
    KEY `idx_holder` (`gang_id`),
    CONSTRAINT `fk_terr_gang` FOREIGN KEY (`gang_id`)
        REFERENCES `cipher_gangs` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Boss-placed world objects: tier-unlock benches/peds and the gang vault
-- container. One row per (gang, kind, unlock_id) — re-placing updates the
-- existing row rather than stacking duplicates.
CREATE TABLE IF NOT EXISTS `cipher_gang_placements` (
    `id`            INT             NOT NULL AUTO_INCREMENT,
    `gang_id`       INT             NOT NULL,
    `kind`          VARCHAR(16)     NOT NULL,            -- 'bench' | 'ped' | 'vault'
    `unlock_id`     VARCHAR(48)     NOT NULL,            -- TierUnlocks id, or 'vault'
    `model`         VARCHAR(64)     NOT NULL,
    `label`         VARCHAR(64)     NOT NULL DEFAULT '',
    `x`             FLOAT           NOT NULL,
    `y`             FLOAT           NOT NULL,
    `z`             FLOAT           NOT NULL,
    `heading`       FLOAT           NOT NULL DEFAULT 0,
    `placed_by`     VARCHAR(64)     NOT NULL DEFAULT '',
    `placed_at`     TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_placement` (`gang_id`, `kind`, `unlock_id`),
    CONSTRAINT `fk_placement_gang` FOREIGN KEY (`gang_id`)
        REFERENCES `cipher_gangs` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `cipher_gang_logs` (
    `id`            INT             NOT NULL AUTO_INCREMENT,
    `gang_id`       INT             NOT NULL,
    `message`       VARCHAR(255)    NOT NULL,
    `created_at`    TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_gang_log` (`gang_id`),
    CONSTRAINT `fk_log_gang` FOREIGN KEY (`gang_id`)
        REFERENCES `cipher_gangs` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Safe to re-run on a DB that already has these tables from an earlier
-- version of this file (MySQL 8 / MariaDB 10.0+ required for IF NOT EXISTS).
ALTER TABLE `cipher_gang_members` ADD COLUMN IF NOT EXISTS `rep` INT NOT NULL DEFAULT 0;
ALTER TABLE `cipher_gang_members` ADD COLUMN IF NOT EXISTS `dues_paid_at` BIGINT NOT NULL DEFAULT 0;
ALTER TABLE `cipher_territories` ADD COLUMN IF NOT EXISTS `label` VARCHAR(64) NOT NULL DEFAULT '';
ALTER TABLE `cipher_territories` ADD COLUMN IF NOT EXISTS `color` INT NOT NULL DEFAULT 0;
ALTER TABLE `cipher_territories` ADD COLUMN IF NOT EXISTS `income` INT NOT NULL DEFAULT 0;
ALTER TABLE `cipher_territories` ADD COLUMN IF NOT EXISTS `coord_x` FLOAT NULL;
ALTER TABLE `cipher_territories` ADD COLUMN IF NOT EXISTS `coord_y` FLOAT NULL;
ALTER TABLE `cipher_territories` ADD COLUMN IF NOT EXISTS `coord_z` FLOAT NULL;
ALTER TABLE `cipher_territories` ADD COLUMN IF NOT EXISTS `assigned_at` BIGINT NOT NULL DEFAULT 0;
