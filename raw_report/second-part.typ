#import "prelude.typ": *

#let second-part = [
#struct[2 часть]
*1. ER-модель*

#image("images/fixly_er.png")

#pagebreak()

*2. Даталогическая модель*

#image("images/fixly_dt.png")

#pagebreak()

*3. Реализация даталогической модели*

```sql
CREATE TABLE IF NOT EXISTS "user" (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email        CITEXT NOT NULL UNIQUE,
    name         VARCHAR(20) NOT NULL,
    surname      VARCHAR(60) NOT NULL,
    last_name    VARCHAR(20),
    phone        VARCHAR(12),
    rating       DECIMAL(2,1),
    status       VARCHAR(20) NOT NULL DEFAULT 'active',
    banned_at    TIMESTAMPTZ,
    ban_reason   TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_user_phone_format CHECK (phone IS NULL OR phone ~ '^\d{10,12}$'),
    CONSTRAINT chk_user_rating CHECK (rating IS NULL OR (rating >= 0 AND rating <= 5)),
    CONSTRAINT chk_user_status CHECK (status IN ('active','banned','deleted'))
);

CREATE TABLE IF NOT EXISTS notification (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    type         VARCHAR(50),
    body         TEXT,
    is_read      BOOLEAN DEFAULT FALSE,
    created_at   TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS blacklist (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id         UUID REFERENCES "user"(id) ON DELETE CASCADE,
    blocked_user_id  UUID REFERENCES "user"(id) ON DELETE CASCADE,
    created_at       TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_blacklist_owner_blocked
    ON blacklist(owner_id, blocked_user_id);

CREATE TABLE IF NOT EXISTS listing (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id           UUID NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    title              VARCHAR(500) NOT NULL,
    description        TEXT,
    price_per_hour     DECIMAL(38,10) NOT NULL,
    deposit_amount     DECIMAL(38,10),
    auto_confirmation  BOOLEAN DEFAULT FALSE,
    status             VARCHAR(30) DEFAULT 'active',
    latitude           DECIMAL(9,6),
    longitude          DECIMAL(9,6),
    created_at         TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_listing_price_nonneg   CHECK (price_per_hour IS NULL OR price_per_hour >= 0),
    CONSTRAINT chk_listing_deposit_nonneg CHECK (deposit_amount IS NULL OR deposit_amount >= 0),
    CONSTRAINT chk_listing_lat            CHECK (latitude  IS NULL OR (latitude  >= -90  AND latitude  <= 90)),
    CONSTRAINT chk_listing_lon            CHECK (longitude IS NULL OR (longitude >= -180 AND longitude <= 180)),
    CONSTRAINT chk_listing_status         CHECK (status IN ('active','paused','archived','blocked'))
);

CREATE TABLE IF NOT EXISTS photo (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id   UUID REFERENCES listing(id) ON DELETE CASCADE,
    url          VARCHAR(255) NOT NULL,
    sort_order   SMALLINT,
    CONSTRAINT uq_photo_listing_sort UNIQUE (listing_id, sort_order)
);

CREATE TABLE IF NOT EXISTS category (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id  UUID REFERENCES category(id) ON DELETE SET NULL,
    name       VARCHAR(100) NOT NULL,
    url_name   VARCHAR(100) UNIQUE
);

CREATE TABLE IF NOT EXISTS listing_category (
    listing_id   UUID REFERENCES listing(id) ON DELETE CASCADE,
    category_id  UUID REFERENCES category(id) ON DELETE CASCADE,
    PRIMARY KEY (listing_id, category_id)
);

CREATE TABLE IF NOT EXISTS favorite (
    user_id     UUID REFERENCES "user"(id) ON DELETE CASCADE,
    listing_id  UUID REFERENCES listing(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, listing_id)
);

CREATE TABLE IF NOT EXISTS availability_slot (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id  UUID NOT NULL REFERENCES listing(id) ON DELETE CASCADE,
    starts_at   TIMESTAMPTZ NOT NULL,
    ends_at     TIMESTAMPTZ NOT NULL,
    note        VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS rental (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    listing_id     UUID NOT NULL REFERENCES listing(id) ON DELETE CASCADE,
    lessor_id      UUID REFERENCES "user"(id),
    lessee_id      UUID REFERENCES "user"(id),
    start_at       TIMESTAMPTZ NOT NULL,
    end_at         TIMESTAMPTZ NOT NULL,
    status         VARCHAR(30) DEFAULT 'pending',
    total_amount   DECIMAL(38,10),
    deposit_amount DECIMAL(38,10),
    created_at     TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    period         tsrange GENERATED ALWAYS AS (tsrange(start_at, end_at, '[)')) STORED,
    CONSTRAINT chk_rental_status CHECK (status IN ('pending','active','cancelled','expired','completed'))
);

CREATE TABLE IF NOT EXISTS payment (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rental_id   UUID REFERENCES rental(id) ON DELETE CASCADE,
    amount      DECIMAL(38,10) NOT NULL,
    status      VARCHAR(20) DEFAULT 'unpaid',
    paid_at     TIMESTAMPTZ,
    external_id VARCHAR(100),
    CONSTRAINT chk_payment_amount_nonneg CHECK (amount >= 0),
    CONSTRAINT chk_payment_status CHECK (status IN ('unpaid','paid','refunded','void'))
);

CREATE TABLE IF NOT EXISTS contract (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rental_id      UUID REFERENCES rental(id) ON DELETE CASCADE,
    status         VARCHAR(30) DEFAULT 'draft',
    signed_at      TIMESTAMPTZ,
    file_url       VARCHAR(255),
    signature_hash VARCHAR(255),
    CONSTRAINT chk_contract_status CHECK (status IN ('draft','sent','signed','cancelled'))
);

CREATE TABLE IF NOT EXISTS review (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lessor_id   UUID REFERENCES "user"(id) ON DELETE SET NULL,
    lessee_id   UUID REFERENCES "user"(id) ON DELETE SET NULL,
    listing_id  UUID REFERENCES listing(id) ON DELETE SET NULL,
    rating      SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    text        TEXT,
    created_at  TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS conversation (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rental_id   UUID NOT NULL REFERENCES rental(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS conversation_pair (
    conversation_id UUID NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (conversation_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_convpair_user ON conversation_pair(user_id);

CREATE TABLE IF NOT EXISTS message (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id  UUID NOT NULL REFERENCES conversation(id) ON DELETE CASCADE,
    sender_id        UUID NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    body             TEXT NOT NULL,
    sent_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_read          BOOLEAN DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS report (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id  UUID REFERENCES "user"(id) ON DELETE SET NULL,
    status       VARCHAR(30) DEFAULT 'open',
    target_type  VARCHAR(30),
    target_id    UUID REFERENCES rental(id),
    reason_body  TEXT,
    created_at   TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    resolved_by  UUID REFERENCES "user"(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS moderation_action (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id      UUID REFERENCES report(id) ON DELETE CASCADE,
    listing_id     UUID REFERENCES listing(id) ON DELETE SET NULL,
    actor_id       UUID REFERENCES "user"(id) ON DELETE SET NULL,
    target_user_id UUID REFERENCES "user"(id) ON DELETE SET NULL,
    action         VARCHAR(50),
    comment        TEXT,
    created_at     TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

```

Код создаёт таблицы исходя из датологической модели. Связи настроены так, чтобы при удалении пользователя автоматически удалялись его объявления, избранное, сообщения и т.д. Так же добавлены проверки на корректные данные.

*4. Реализация тригеров и индексов*

```sql

DO $$
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM pg_constraint
            WHERE conname = 'rental_no_overlap'
        ) THEN
            ALTER TABLE rental
                ADD CONSTRAINT rental_no_overlap
                    EXCLUDE USING gist (listing_id WITH =, period WITH &&);
        END IF;
    END $$;

DO $$
    BEGIN
        IF EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE conname = 'avail_no_overlap'
              AND conrelid = 'availability_slot'::regclass
        ) THEN
            ALTER TABLE availability_slot
                DROP CONSTRAINT avail_no_overlap;
        END IF;
        ALTER TABLE availability_slot
            ADD CONSTRAINT avail_no_overlap
                EXCLUDE USING gist (
                listing_id WITH =,
                tstzrange(starts_at, ends_at, '[)') WITH &&
                );
END $$;


CREATE INDEX IF NOT EXISTS idx_notification_user      ON notification(user_id);
CREATE INDEX IF NOT EXISTS idx_blacklist_owner        ON blacklist(owner_id);
CREATE INDEX IF NOT EXISTS idx_blacklist_blocked      ON blacklist(blocked_user_id);
CREATE INDEX IF NOT EXISTS idx_listing_owner          ON listing(owner_id);
CREATE INDEX IF NOT EXISTS idx_photo_listing          ON photo(listing_id);
CREATE INDEX IF NOT EXISTS idx_listing_category_cat   ON listing_category(category_id);
CREATE INDEX IF NOT EXISTS idx_favorite_user          ON favorite(user_id);
CREATE INDEX IF NOT EXISTS idx_favorite_listing       ON favorite(listing_id);
CREATE INDEX IF NOT EXISTS idx_avail_slot_lid_time    ON availability_slot(listing_id, starts_at, ends_at);
CREATE INDEX IF NOT EXISTS idx_rental_lid_time        ON rental(listing_id, start_at, end_at);
CREATE INDEX IF NOT EXISTS idx_rental_lessor          ON rental(lessor_id);
CREATE INDEX IF NOT EXISTS idx_rental_lessee          ON rental(lessee_id);
CREATE INDEX IF NOT EXISTS idx_payment_rental         ON payment(rental_id);
CREATE INDEX IF NOT EXISTS idx_contract_rental        ON contract(rental_id);
CREATE INDEX IF NOT EXISTS idx_review_listing         ON review(listing_id);
CREATE INDEX IF NOT EXISTS idx_review_lessor          ON review(lessor_id);
CREATE INDEX IF NOT EXISTS idx_review_lessee          ON review(lessee_id);
CREATE INDEX IF NOT EXISTS idx_conversation_rental    ON conversation(rental_id);
CREATE INDEX IF NOT EXISTS idx_message_conversation   ON message(conversation_id);
CREATE INDEX IF NOT EXISTS idx_message_sender         ON message(sender_id);
CREATE INDEX IF NOT EXISTS idx_report_reporter        ON report(reporter_id);
CREATE INDEX IF NOT EXISTS idx_report_target          ON report(target_id);
CREATE INDEX IF NOT EXISTS idx_moderation_report      ON moderation_action(report_id);
CREATE INDEX IF NOT EXISTS idx_moderation_target_user ON moderation_action(target_user_id);
CREATE INDEX IF NOT EXISTS idx_notification_user_read ON notification(user_id, is_read, created_at);


CREATE OR REPLACE FUNCTION fn_moderation_action_apply() RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.action IS NOT NULL AND LOWER(NEW.action) LIKE 'ban%' AND NEW.target_user_id IS NOT NULL THEN
        UPDATE "user"
        SET status = 'banned',
            banned_at = now(),
            ban_reason = COALESCE(NEW.comment, ban_reason)
        WHERE id = NEW.target_user_id;
    END IF;

    IF NEW.action IS NOT NULL AND LOWER(NEW.action) IN ('unban','restore') AND NEW.target_user_id IS NOT NULL THEN
        UPDATE "user"
        SET status = 'active',
            banned_at = NULL,
            ban_reason = NULL
        WHERE id = NEW.target_user_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_moderation_action_apply ON moderation_action;
CREATE TRIGGER trg_moderation_action_apply
    AFTER INSERT OR UPDATE ON moderation_action
    FOR EACH ROW EXECUTE FUNCTION fn_moderation_action_apply();

CREATE OR REPLACE FUNCTION fn_rental_before_ins_upd() RETURNS trigger
    LANGUAGE plpgsql AS $$
DECLARE
    conflict_count int;
BEGIN
    IF NEW.start_at IS NULL OR NEW.end_at IS NULL THEN
        RAISE EXCEPTION 'rental.start_at and rental.end_at must be NOT NULL';
    END IF;

    IF NOT (NEW.start_at < NEW.end_at) THEN
        RAISE EXCEPTION 'rental.start_at must be less than rental.end_at (got % >= %)', NEW.start_at, NEW.end_at;
    END IF;

    IF NEW.end_at <= now() THEN
        NEW.status := 'expired';
        RETURN NEW;
    END IF;

    SELECT COUNT(*) INTO conflict_count
    FROM rental r
    WHERE r.listing_id = NEW.listing_id
      AND r.id IS DISTINCT FROM NEW.id
      AND r.status IN ('pending','active')
      AND NOT (r.end_at <= NEW.start_at OR r.start_at >= NEW.end_at);

    IF conflict_count > 0 THEN
        RAISE EXCEPTION 'double booking detected: listing % already has % overlapping rental(s)', NEW.listing_id, conflict_count;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_rental_before_ins_upd ON rental;
CREATE TRIGGER trg_rental_before_ins_upd
    BEFORE INSERT OR UPDATE ON rental
    FOR EACH ROW EXECUTE FUNCTION fn_rental_before_ins_upd();

CREATE OR REPLACE FUNCTION fn_user_before_delete() RETURNS trigger
    LANGUAGE plpgsql AS $$
DECLARE
    cnt int;
BEGIN
    SELECT COUNT(*) INTO cnt
    FROM rental r
    WHERE (r.lessor_id = OLD.id OR r.lessee_id = OLD.id)
      AND r.status IN ('pending','active');

    IF cnt > 0 THEN
        RAISE EXCEPTION 'cannot delete user %: has % active/pending rental(s)', OLD.id, cnt;
    END IF;

    SELECT COUNT(*) INTO cnt
    FROM payment p
             JOIN rental r ON p.rental_id = r.id
    WHERE (r.lessor_id = OLD.id OR r.lessee_id = OLD.id)
      AND p.status <> 'refunded';

    IF cnt > 0 THEN
        RAISE EXCEPTION 'cannot delete user %: has % non-refunded payment(s)', OLD.id, cnt;
    END IF;

    RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_before_delete ON "user";
CREATE TRIGGER trg_user_before_delete
    BEFORE DELETE ON "user"
    FOR EACH ROW EXECUTE FUNCTION fn_user_before_delete();

CREATE OR REPLACE FUNCTION fn_payment_before_ins_upd() RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.amount IS NULL OR NEW.amount < 0 THEN
        RAISE EXCEPTION 'payment.amount must be non-negative';
    END IF;

    IF LOWER(COALESCE(NEW.status,'')) = 'paid' THEN
        IF NEW.paid_at IS NULL THEN
            NEW.paid_at := now();
        END IF;
    ELSIF LOWER(COALESCE(NEW.status,'')) IN ('unpaid','void','refunded') THEN
        NEW.paid_at := NULL;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_payment_before_ins_upd ON payment;
CREATE TRIGGER trg_payment_before_ins_upd
    BEFORE INSERT OR UPDATE ON payment
    FOR EACH ROW EXECUTE FUNCTION fn_payment_before_ins_upd();

CREATE OR REPLACE FUNCTION fn_mark_expired_rentals() RETURNS void
    LANGUAGE plpgsql AS $$
DECLARE
    rec RECORD;
BEGIN
    WITH expired AS (
        UPDATE rental r
            SET status = 'expired'
            WHERE r.end_at <= now()
                AND r.status IN ('pending','active')
            RETURNING r.id, r.lessor_id, r.lessee_id, r.listing_id
    )
    INSERT INTO notification(id, user_id, type, body, created_at)
    SELECT gen_random_uuid(),
           u,
           'rental_expired',
           CONCAT('Rental ', e.id::text, ' for listing ', e.listing_id::text, ' has expired.'),
           now()
    FROM expired e
             CROSS JOIN LATERAL (VALUES (e.lessor_id), (e.lessee_id)) AS v(u)
    WHERE v.u IS NOT NULL;

    FOR rec IN
        SELECT DISTINCT listing_id
        FROM rental
        WHERE status = 'expired' AND end_at <= now()
        LOOP
            IF NOT EXISTS (
                SELECT 1
                FROM rental r2
                WHERE r2.listing_id = rec.listing_id
                  AND r2.status IN ('pending','active')
            ) THEN
                UPDATE listing
                SET status = 'active'
                WHERE id = rec.listing_id;
            END IF;
        END LOOP;
END;
$$;


DO $do$
    DECLARE
        v_jobid integer;
    BEGIN
        SELECT jobid
        INTO v_jobid
        FROM cron.job
        WHERE jobname = 'mark_expired_rentals_hourly'
        LIMIT 1;

        IF v_jobid IS NOT NULL THEN
            PERFORM cron.unschedule(v_jobid);
        END IF;

        PERFORM cron.schedule(
                'mark_expired_rentals_hourly',
                '0 * * * *',
                'SELECT public.fn_mark_expired_rentals();'
                );
    END
$do$;
```
*Индексы*

+ Индексы по внешним ключам

    Созданы на полях вроде `user_id`, `listing_id`, `rental_id`, `report_id`.
    Они ускоряют выборку данных, связанных с конкретным пользователем, объявлением или арендой.

+ Уникальные индексы

 - `ux_blacklist_owner_blocked` — не позволяет владельцу дважды заблокировать одного и того же пользователя.
 - Уникальный индекс на `email` (через тип `citext`) обеспечивает уникальность без учёта регистра,
   чтобы `User@Mail.com` и `user@mail.com` считались одним адресом.

+ GiST-индексы

  Используются для проверки пересечения временных интервалов (`rental_no_overlap` и `avail_no_overlap`).
  Это позволяет быстро выявлять и предотвращать пересечения периодов аренды и доступности.

+ Индексы для ускорения выборок

  Созданы на полях вроде `is_read`, `created_at`, `lessor_id`, `lessee_id` и других.
  Они ускоряют запросы вроде «все непрочитанные уведомления» или «все мои аренды».


*Триггеры*

+ Триггер: *fn_moderation_action_apply* срабатывает после вставки или обновления записи в таблице `moderation_action`.

    Он автоматически блокирует или разблокирует пользователя в зависимости от значения поля `action`:

        - Если действие начинается со слова *ban*, пользователь получает статус `banned`, фиксируется дата и причина блокировки.

        - Если действие *unban* или *restore*, пользователь снова становится `active`.

    *Зачем:* автоматизация изменения статуса пользователя без ручного вмешательства.


+ Триггер: *fn_rental_before_ins_upd* cрабатывает перед вставкой или обновлением записи в таблице `rental`.

    Он:

    - Проверяет корректность дат (`start_at < end_at`);

    - Автоматически помечает просроченные аренды как `expired`;

    - Запрещает пересекающиеся аренды для одного объявления (double booking).

    *Зачем:* предотвращает ошибки при бронировании и сохраняет корректность периодов аренды.


+ Триггер: *fn_user_before_delete* cрабатывает перед удалением пользователя.

    Он не позволяет удалить пользователя, если:

    - у него есть активные или ожидающие аренды;

    - есть платежи, которые ещё не возвращены.

    *Зачем:* сохраняет целостность данных и предотвращает удаление пользователей с незавершёнными операциями.


+ Триггер: *fn_payment_before_ins_upd* работает перед вставкой или обновлением записи в таблице `payment`.

    Он:

    - Проверяет, что сумма не отрицательная;

    - При статусе `paid` автоматически проставляет дату оплаты `paid_at`;

    - При смене статуса на `unpaid` или `refunded` очищает дату оплаты.

    *Зачем:* автоматизирует корректное заполнение информации о платежах.


+ Функция: *fn_mark_expired_rentals* функция, запускаемая по расписанию через `pg_cron`.

    Она:
    - Находит аренды, у которых истёк срок, и ставит им статус `expired`;

    - Создаёт уведомления для арендодателя и арендатора;

    - Если по объявлению нет активных аренд, возвращает его в статус `active`.

    *Зачем:* автоматически обновляет состояние аренд и уведомляет пользователей.


*5. Заполнение тестовыми данными*

```sql

BEGIN;

-- Users: несколько владельцев, арендаторов, администратор и заблокированные аккаунты
INSERT INTO "user" (id, email, name, phone, rating, status, banned_at, ban_reason, created_at)
VALUES
    ('11111111-1111-1111-1111-111111111111', 'owner@fixly.test',   'Ivan Owner',    '79210000001', 4.8, 'active', NULL, NULL, '2024-06-01T09:00:00Z'),
    ('22222222-2222-2222-2222-222222222222', 'lessee@fixly.test',  'Anna Lessee',   '79210000002', 4.5, 'active', NULL, NULL, '2024-06-02T09:15:00Z'),
    ('33333333-3333-3333-3333-333333333333', 'admin@fixly.test',   'Alice Admin',   '79210000003', NULL, 'active', NULL, NULL, '2024-06-03T08:45:00Z'),
    ('44444444-4444-4444-4444-444444444444', 'blocked@fixly.test', 'Boris Blocked', '79210000004', 3.2, 'banned', '2024-05-20T12:00:00Z', 'Fraud suspicion', '2024-04-20T12:00:00Z'),
    ('55555555-5555-5555-5555-555555555555', 'owner2@fixly.test',  'Sergey Builder', '79210000005', 4.9, 'active', NULL, NULL, '2024-06-05T10:00:00Z'),
    ('66666666-6666-6666-6666-666666666666', 'lessee2@fixly.test', 'Olga Planner',  '79210000006', 4.2, 'active', NULL, NULL, '2024-06-06T12:30:00Z'),
    ('77777777-7777-7777-7777-777777777777', 'support@fixly.test', 'Support Bot',   NULL,           NULL, 'active', NULL, NULL, '2024-06-07T07:45:00Z'),
    ('88888888-8888-8888-8888-888888888888', 'newbie@fixly.test',  'Mikhail Newbie','79210000007', NULL, 'active', NULL, NULL, '2024-06-08T08:00:00Z'),
    ('99999999-8888-7777-6666-555555555555', 'suspended@fixly.test', 'Pavel Suspended', '79210000008', 2.5, 'banned', '2024-05-30T09:30:00Z', 'Payment disputes', '2024-04-25T11:00:00Z')
ON CONFLICT (id) DO NOTHING;

-- Categories hierarchy
INSERT INTO category (id, parent_id, name, url_name)
VALUES
    ('aaaaaaaa-0000-0000-0000-000000000000', NULL, 'Power Tools', 'power-tools'),
    ('bbbbbbbb-0000-0000-0000-000000000000', 'aaaaaaaa-0000-0000-0000-000000000000', 'Drills', 'drills'),
    ('cccccccc-0000-0000-0000-000000000000', 'aaaaaaaa-0000-0000-0000-000000000000', 'Saws',   'saws'),
    ('dddddddd-0000-0000-0000-000000000000', NULL, 'Gardening Tools', 'gardening-tools'),
    ('eeeeeeee-0000-0000-0000-000000000000', 'dddddddd-0000-0000-0000-000000000000', 'Trimmers', 'trimmers'),
    ('ffffffff-0000-0000-0000-000000000000', 'dddddddd-0000-0000-0000-000000000000', 'Pressure Washers', 'pressure-washers'),
    ('aaaa9999-0000-0000-0000-000000000000', NULL, 'Hand Tools', 'hand-tools'),
    ('bbbb9999-0000-0000-0000-000000000000', 'aaaa9999-0000-0000-0000-000000000000', 'Ladders', 'ladders')
ON CONFLICT (id) DO NOTHING;

-- Listings
INSERT INTO listing (id, owner_id, title, description, price_per_hour, deposit_amount, auto_confirmation, status, latitude, longitude, created_at)
VALUES
    ('aaaa1111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111',
     'Makita Cordless Drill', '18V drill with two batteries and charger.', 10.50, 30.00, TRUE, 'active', 59.9386, 30.3141, '2024-06-10T10:00:00Z'),
    ('bbbb1111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111',
     'Bosch Circular Saw', 'Professional-grade circular saw with laser guide.', 14.00, 40.00, FALSE, 'active', 59.9310, 30.3600, '2024-06-12T11:30:00Z'),
    ('cccc1111-1111-1111-1111-111111111111', '55555555-5555-5555-5555-555555555555',
     'Stihl Grass Trimmer', 'Battery trimmer with spare line cassette.', 9.00, 20.00, TRUE, 'active', 55.7558, 37.6176, '2024-06-15T08:30:00Z'),
    ('dddd1111-1111-1111-1111-111111111111', '55555555-5555-5555-5555-555555555555',
     'Karcher Pressure Washer', 'High-pressure washer ideal for patios and cars.', 18.00, 50.00, FALSE, 'paused', 55.7600, 37.6200, '2024-06-18T09:45:00Z'),
    ('eeee1111-1111-1111-1111-111111111111', '55555555-5555-5555-5555-555555555555',
     'Aluminum Extension Ladder', '5 meter ladder suitable for outdoor use.', 7.50, NULL, TRUE, 'active', 59.9500, 30.3200, '2024-06-20T07:50:00Z'),
    ('ffff1111-1111-1111-1111-111111111111', '88888888-8888-8888-8888-888888888888',
     'DeWalt Impact Driver', 'Compact brushless impact driver with bits kit.', 11.00, 25.00, TRUE, 'archived', 59.9400, 30.3000, '2024-06-22T10:20:00Z')
ON CONFLICT (id) DO NOTHING;

-- Listing to category assignments
INSERT INTO listing_category (listing_id, category_id)
VALUES
    ('aaaa1111-1111-1111-1111-111111111111', 'bbbbbbbb-0000-0000-0000-000000000000'),
    ('bbbb1111-1111-1111-1111-111111111111', 'cccccccc-0000-0000-0000-000000000000'),
    ('cccc1111-1111-1111-1111-111111111111', 'eeeeeeee-0000-0000-0000-000000000000'),
    ('dddd1111-1111-1111-1111-111111111111', 'ffffffff-0000-0000-0000-000000000000'),
    ('eeee1111-1111-1111-1111-111111111111', 'bbbb9999-0000-0000-0000-000000000000'),
    ('ffff1111-1111-1111-1111-111111111111', 'bbbbbbbb-0000-0000-0000-000000000000')
ON CONFLICT DO NOTHING;

-- Photos
INSERT INTO photo (listing_id, url, sort_order)
VALUES
    ('aaaa1111-1111-1111-1111-111111111111', 'https://cdn.fixly.test/drill/front.jpg', 0),
    ('aaaa1111-1111-1111-1111-111111111111', 'https://cdn.fixly.test/drill/case.jpg', 1),
    ('bbbb1111-1111-1111-1111-111111111111', 'https://cdn.fixly.test/saw/front.jpg', 0),
    ('cccc1111-1111-1111-1111-111111111111', 'https://cdn.fixly.test/trimmer/front.jpg', 0),
    ('cccc1111-1111-1111-1111-111111111111', 'https://cdn.fixly.test/trimmer/battery.jpg', 1),
    ('dddd1111-1111-1111-1111-111111111111', 'https://cdn.fixly.test/washer/front.jpg', 0),
    ('eeee1111-1111-1111-1111-111111111111', 'https://cdn.fixly.test/ladder/full.jpg', 0),
    ('ffff1111-1111-1111-1111-111111111111', 'https://cdn.fixly.test/impact-driver/front.jpg', 0)
ON CONFLICT (listing_id, sort_order) DO NOTHING;

-- Availability slots
INSERT INTO availability_slot (listing_id, starts_at, ends_at, note)
VALUES
    ('aaaa1111-1111-1111-1111-111111111111', '2024-07-01T08:00:00Z', '2024-07-10T22:00:00Z', 'Week-long availability'),
    ('bbbb1111-1111-1111-1111-111111111111', '2024-07-03T08:00:00Z', '2024-07-15T20:00:00Z', 'Available after maintenance'),
    ('cccc1111-1111-1111-1111-111111111111', '2024-07-05T07:00:00Z', '2024-07-20T19:00:00Z', 'Peak season'),
    ('dddd1111-1111-1111-1111-111111111111', '2024-07-08T09:00:00Z', '2024-07-30T18:00:00Z', 'Requires 24h notice'),
    ('eeee1111-1111-1111-1111-111111111111', '2024-07-01T08:00:00Z', '2024-07-31T21:00:00Z', 'Flexible hours'),
    ('ffff1111-1111-1111-1111-111111111111', '2024-06-25T09:00:00Z', '2024-07-05T20:00:00Z', 'Last season availability')
ON CONFLICT DO NOTHING;

-- Favorites
INSERT INTO favorite (user_id, listing_id, created_at)
VALUES
    ('22222222-2222-2222-2222-222222222222', 'aaaa1111-1111-1111-1111-111111111111', '2024-06-15T09:00:00Z'),
    ('66666666-6666-6666-6666-666666666666', 'cccc1111-1111-1111-1111-111111111111', '2024-06-20T12:00:00Z'),
    ('88888888-8888-8888-8888-888888888888', 'bbbb1111-1111-1111-1111-111111111111', '2024-06-21T14:30:00Z')
ON CONFLICT DO NOTHING;

-- Blacklist (owner blocks banned user)
INSERT INTO blacklist (id, owner_id, blocked_user_id, created_at)
VALUES
    ('99999999-9999-9999-9999-999999999999', '11111111-1111-1111-1111-111111111111', '44444444-4444-4444-4444-444444444444', '2024-06-05T10:00:00Z'),
    ('88888888-9999-9999-9999-999999999999', '55555555-5555-5555-5555-555555555555', '99999999-8888-7777-6666-555555555555', '2024-06-25T08:00:00Z')
ON CONFLICT (owner_id, blocked_user_id) DO NOTHING;

-- Rentals
INSERT INTO rental (id, listing_id, lessor_id, lessee_id, start_at, end_at, status, total_amount, deposit_amount, created_at)
VALUES
    ('00000000-0000-0000-0000-000000000101', 'aaaa1111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
     '2024-07-02T10:00:00Z', '2024-07-02T16:00:00Z', 'completed', 63.00, 30.00, '2024-07-01T12:00:00Z'),
    ('00000000-0000-0000-0000-000000000102', 'bbbb1111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
     '2024-07-06T09:00:00Z', '2024-07-06T17:00:00Z', 'active', 112.00, 40.00, '2024-07-04T10:00:00Z'),
    ('00000000-0000-0000-0000-000000000103', 'cccc1111-1111-1111-1111-111111111111', '55555555-5555-5555-5555-555555555555', '66666666-6666-6666-6666-666666666666',
     '2024-07-12T08:00:00Z', '2024-07-12T18:00:00Z', 'pending', 90.00, 20.00, '2024-07-10T09:10:00Z'),
    ('00000000-0000-0000-0000-000000000104', 'dddd1111-1111-1111-1111-111111111111', '55555555-5555-5555-5555-555555555555', '66666666-6666-6666-6666-666666666666',
     '2024-07-18T09:00:00Z', '2024-07-18T13:00:00Z', 'cancelled', 72.00, 50.00, '2024-07-16T08:40:00Z'),
    ('00000000-0000-0000-0000-000000000105', 'eeee1111-1111-1111-1111-111111111111', '55555555-5555-5555-5555-555555555555', '22222222-2222-2222-2222-222222222222',
     '2024-07-14T09:00:00Z', '2024-07-14T13:00:00Z', 'expired', 30.00, NULL, '2024-07-12T11:00:00Z'),
    ('00000000-0000-0000-0000-000000000106', 'ffff1111-1111-1111-1111-111111111111', '88888888-8888-8888-8888-888888888888', '66666666-6666-6666-6666-666666666666',
     '2024-06-28T10:00:00Z', '2024-06-28T15:00:00Z', 'completed', 55.00, 25.00, '2024-06-26T10:00:00Z')
ON CONFLICT (id) DO NOTHING;

-- Payments
INSERT INTO payment (id, rental_id, amount, status, paid_at, external_id)
VALUES
    ('00000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-000000000101', 93.00, 'paid', '2024-07-02T09:30:00Z', 'PAY-2024-0001'),
    ('00000000-0000-0000-0000-000000000202', '00000000-0000-0000-0000-000000000102', 112.00, 'unpaid', NULL, NULL),
    ('00000000-0000-0000-0000-000000000203', '00000000-0000-0000-0000-000000000103', 90.00, 'void', NULL, 'PAY-2024-0003'),
    ('00000000-0000-0000-0000-000000000204', '00000000-0000-0000-0000-000000000104', 72.00, 'refunded', '2024-07-17T08:15:00Z', 'PAY-2024-0004'),
    ('00000000-0000-0000-0000-000000000205', '00000000-0000-0000-0000-000000000105', 30.00, 'paid', '2024-07-14T08:50:00Z', 'PAY-2024-0005'),
    ('00000000-0000-0000-0000-000000000206', '00000000-0000-0000-0000-000000000106', 55.00, 'paid', '2024-06-27T18:00:00Z', 'PAY-2024-0006')
ON CONFLICT (id) DO NOTHING;

-- Contracts
INSERT INTO contract (id, rental_id, status, signed_at, file_url, signature_hash)
VALUES
    ('00000000-0000-0000-0000-000000000301', '00000000-0000-0000-0000-000000000101', 'signed', '2024-07-01T18:00:00Z', 'https://files.fixly.test/contracts/rental-0101.pdf', 'sha256:contract-sample-1'),
    ('00000000-0000-0000-0000-000000000302', '00000000-0000-0000-0000-000000000102', 'sent', NULL, 'https://files.fixly.test/contracts/rental-0102.pdf', 'sha256:contract-sample-2'),
    ('00000000-0000-0000-0000-000000000303', '00000000-0000-0000-0000-000000000103', 'draft', NULL, NULL, NULL),
    ('00000000-0000-0000-0000-000000000304', '00000000-0000-0000-0000-000000000104', 'cancelled', NULL, 'https://files.fixly.test/contracts/rental-0104.pdf', 'sha256:contract-sample-4'),
    ('00000000-0000-0000-0000-000000000305', '00000000-0000-0000-0000-000000000105', 'signed', '2024-07-13T18:00:00Z', 'https://files.fixly.test/contracts/rental-0105.pdf', 'sha256:contract-sample-5')
ON CONFLICT (id) DO NOTHING;

-- Reviews
INSERT INTO review (lessor_id, lessee_id, listing_id, rating, text, created_at)
VALUES
    ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'aaaa1111-1111-1111-1111-111111111111', 5,
     'Great communication and timely return.', '2024-07-03T09:00:00Z'),
    ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'aaaa1111-1111-1111-1111-111111111111', 5,
     'Tool was in perfect condition.', '2024-07-03T09:30:00Z'),
    ('55555555-5555-5555-5555-555555555555', '66666666-6666-6666-6666-666666666666', 'cccc1111-1111-1111-1111-111111111111', 4,
     'Returned with low battery but overall fine.', '2024-07-13T20:00:00Z'),
    ('66666666-6666-6666-6666-666666666666', '55555555-5555-5555-5555-555555555555', 'cccc1111-1111-1111-1111-111111111111', 5,
     'Owner was very helpful and flexible.', '2024-07-13T20:30:00Z'),
    ('88888888-8888-8888-8888-888888888888', '66666666-6666-6666-6666-666666666666', 'ffff1111-1111-1111-1111-111111111111', 4,
     'Driver performed as expected.', '2024-06-29T10:00:00Z')
ON CONFLICT DO NOTHING;

-- Conversations
INSERT INTO conversation (id, rental_id, created_at)
VALUES
    ('00000000-0000-0000-0000-000000000501', '00000000-0000-0000-0000-000000000101', '2024-07-01T13:00:00Z'),
    ('00000000-0000-0000-0000-000000000502', '00000000-0000-0000-0000-000000000102', '2024-07-04T11:00:00Z'),
    ('00000000-0000-0000-0000-000000000503', '00000000-0000-0000-0000-000000000103', '2024-07-10T10:00:00Z'),
    ('00000000-0000-0000-0000-000000000504', '00000000-0000-0000-0000-000000000106', '2024-06-26T11:00:00Z')
ON CONFLICT (id) DO NOTHING;

INSERT INTO conversation_pair (conversation_id, user_id, created_at)
VALUES
    ('00000000-0000-0000-0000-000000000501', '11111111-1111-1111-1111-111111111111', '2024-07-01T13:00:00Z'),
    ('00000000-0000-0000-0000-000000000501', '22222222-2222-2222-2222-222222222222', '2024-07-01T13:00:00Z'),
    ('00000000-0000-0000-0000-000000000502', '11111111-1111-1111-1111-111111111111', '2024-07-04T11:00:00Z'),
    ('00000000-0000-0000-0000-000000000502', '22222222-2222-2222-2222-222222222222', '2024-07-04T11:00:00Z'),
    ('00000000-0000-0000-0000-000000000503', '55555555-5555-5555-5555-555555555555', '2024-07-10T10:00:00Z'),
    ('00000000-0000-0000-0000-000000000503', '66666666-6666-6666-6666-666666666666', '2024-07-10T10:00:00Z'),
    ('00000000-0000-0000-0000-000000000504', '88888888-8888-8888-8888-888888888888', '2024-06-26T11:00:00Z'),
    ('00000000-0000-0000-0000-000000000504', '66666666-6666-6666-6666-666666666666', '2024-06-26T11:00:00Z')
ON CONFLICT DO NOTHING;

INSERT INTO message (conversation_id, sender_id, body, sent_at, is_read)
VALUES
    ('00000000-0000-0000-0000-000000000501', '22222222-2222-2222-2222-222222222222', 'Hi! Can I pick it up tomorrow at 10?', '2024-07-01T13:05:00Z', TRUE),
    ('00000000-0000-0000-0000-000000000501', '11111111-1111-1111-1111-111111111111', 'Sure, I will be available at the workshop.', '2024-07-01T13:06:00Z', FALSE),
    ('00000000-0000-0000-0000-000000000502', '22222222-2222-2222-2222-222222222222', 'Could you confirm the pickup location?', '2024-07-04T11:05:00Z', TRUE),
    ('00000000-0000-0000-0000-000000000502', '11111111-1111-1111-1111-111111111111', 'Same workshop as before, sent map pin.', '2024-07-04T11:06:00Z', TRUE),
    ('00000000-0000-0000-0000-000000000503', '66666666-6666-6666-6666-666666666666', 'Can we shorten booking to 6 hours?', '2024-07-10T10:10:00Z', FALSE),
    ('00000000-0000-0000-0000-000000000503', '55555555-5555-5555-5555-555555555555', 'Yes, updated the request on the platform.', '2024-07-10T10:12:00Z', FALSE),
    ('00000000-0000-0000-0000-000000000504', '66666666-6666-6666-6666-666666666666', 'Thanks for the quick confirmation!', '2024-06-26T11:05:00Z', TRUE)
ON CONFLICT DO NOTHING;

-- Notifications
INSERT INTO notification (user_id, type, body, is_read, created_at)
VALUES
    ('11111111-1111-1111-1111-111111111111', 'rental_request', 'New rental request 00000000-0000-0000-0000-000000000102 from Anna.', FALSE, '2024-07-04T10:01:00Z'),
    ('22222222-2222-2222-2222-222222222222', 'rental_confirmed', 'Rental 00000000-0000-0000-0000-000000000101 confirmed automatically.', TRUE, '2024-07-01T12:05:00Z'),
    ('55555555-5555-5555-5555-555555555555', 'rental_request', 'New rental request 00000000-0000-0000-0000-000000000103 from Olga.', FALSE, '2024-07-10T09:11:00Z'),
    ('66666666-6666-6666-6666-666666666666', 'rental_pending', 'Rental 00000000-0000-0000-0000-000000000103 is pending confirmation.', FALSE, '2024-07-10T09:12:00Z'),
    ('66666666-6666-6666-6666-666666666666', 'payment_refunded', 'Payment for rental 00000000-0000-0000-0000-000000000104 has been refunded.', TRUE, '2024-07-17T08:20:00Z'),
    ('55555555-5555-5555-5555-555555555555', 'rental_expired', 'Rental 00000000-0000-0000-0000-000000000105 expired without completion.', FALSE, '2024-07-15T09:00:00Z'),
    ('88888888-8888-8888-8888-888888888888', 'rental_review', 'Remember to review rental 00000000-0000-0000-0000-000000000106.', FALSE, '2024-06-29T09:00:00Z')
ON CONFLICT DO NOTHING;

-- Report and moderation action
INSERT INTO report (id, reporter_id, status, target_type, target_id, reason_body, created_at, resolved_by)
VALUES
    ('00000000-0000-0000-0000-000000000601', '22222222-2222-2222-2222-222222222222', 'open', 'rental', '00000000-0000-0000-0000-000000000102', 'Pickup was delayed by 2 hours.', '2024-07-07T12:00:00Z', '33333333-3333-3333-3333-333333333333'),
    ('00000000-0000-0000-0000-000000000602', '66666666-6666-6666-6666-666666666666', 'closed', 'rental', '00000000-0000-0000-0000-000000000104', 'Washer leaked water on pickup point.', '2024-07-18T14:00:00Z', '33333333-3333-3333-3333-333333333333')
ON CONFLICT (id) DO NOTHING;

INSERT INTO moderation_action (id, report_id, listing_id, actor_id, target_user_id, action, comment, created_at)
VALUES
    ('00000000-0000-0000-0000-000000000701', '00000000-0000-0000-0000-000000000601', 'bbbb1111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'pause', 'Listing paused for manual inspection.', '2024-07-07T15:00:00Z'),
    ('00000000-0000-0000-0000-000000000702', '00000000-0000-0000-0000-000000000602', 'dddd1111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333', '55555555-5555-5555-5555-555555555555', 'archive', 'Archived after repeated complaints.', '2024-07-19T09:00:00Z')
ON CONFLICT (id) DO NOTHING;

COMMIT;
```

*6. Функции*

```sql
CREATE OR REPLACE FUNCTION fn_register_user(
    p_email          citext,
    p_name           varchar,
    p_phone          varchar DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id uuid;
    v_name    text;
BEGIN
    IF p_email IS NULL OR trim(p_email::text) = '' THEN
        RAISE EXCEPTION 'E-mail обязателен для регистрации';
    END IF;

    IF p_phone IS NOT NULL AND p_phone !~ '^\d{10,12}$' THEN
        RAISE EXCEPTION 'Телефон должен содержать от 10 до 12 цифр (передано: %)', p_phone;
    END IF;

    SELECT id
      INTO v_user_id
      FROM "user"
     WHERE email = p_email;
    IF FOUND THEN
        RAISE EXCEPTION 'Пользователь с e-mail % уже существует', p_email;
    END IF;

    v_name := nullif(trim(p_name), '');

    INSERT INTO "user" (email, name, phone)
    VALUES (p_email, COALESCE(v_name, 'Unnamed user'), p_phone)
    RETURNING id INTO v_user_id;

    RETURN v_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION fn_search_listings(
    p_query           text DEFAULT NULL,
    p_category_ids    uuid[] DEFAULT NULL,
    p_min_price       numeric DEFAULT NULL,
    p_max_price       numeric DEFAULT NULL,
    p_available_from  timestamptz DEFAULT NULL,
    p_available_to    timestamptz DEFAULT NULL,
    p_latitude        numeric DEFAULT NULL,
    p_longitude       numeric DEFAULT NULL,
    p_radius_km       numeric DEFAULT NULL
) RETURNS TABLE (
    listing_id        uuid,
    owner_id          uuid,
    title             text,
    description       text,
    price_per_hour    numeric,
    deposit_amount    numeric,
    auto_confirmation boolean,
    latitude          numeric,
    longitude         numeric,
    distance_km       numeric,
    category_ids      uuid[],
    is_available      boolean
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        l.id,
        l.owner_id,
        l.title,
        l.description,
        l.price_per_hour,
        l.deposit_amount,
        l.auto_confirmation,
        l.latitude,
        l.longitude,
        geo.distance_km,
        COALESCE(array_agg(DISTINCT lc.category_id) FILTER (WHERE lc.category_id IS NOT NULL), ARRAY[]::uuid[]) AS category_ids,
        CASE
            WHEN p_available_from IS NULL OR p_available_to IS NULL THEN NULL
            ELSE (avail.slot_ok AND NOT avail.has_conflict)
        END AS is_available
    FROM listing AS l
    LEFT JOIN listing_category AS lc ON lc.listing_id = l.id
    CROSS JOIN LATERAL (
        SELECT CASE
            WHEN p_latitude IS NULL OR p_longitude IS NULL OR l.latitude IS NULL OR l.longitude IS NULL THEN NULL
            ELSE (
                acos(
                    LEAST(1, GREATEST(-1,
                        sin(radians(p_latitude)) * sin(radians(l.latitude)) +
                        cos(radians(p_latitude)) * cos(radians(l.latitude)) *
                        cos(radians(l.longitude - p_longitude))
                    ))
                ) * 6371.0
            )
        END AS distance_km
    ) AS geo
    CROSS JOIN LATERAL (
        SELECT
            CASE
                WHEN p_available_from IS NULL OR p_available_to IS NULL THEN TRUE
                ELSE EXISTS (
                    SELECT 1
                      FROM availability_slot AS s
                     WHERE s.listing_id = l.id
                       AND s.starts_at <= p_available_from
                       AND s.ends_at   >= p_available_to
                )
            END AS slot_ok,
            CASE
                WHEN p_available_from IS NULL OR p_available_to IS NULL THEN FALSE
                ELSE EXISTS (
                    SELECT 1
                      FROM rental AS r
                     WHERE r.listing_id = l.id
                       AND r.status IN ('pending','active')
                       AND NOT (r.end_at <= p_available_from OR r.start_at >= p_available_to)
                )
            END AS has_conflict
    ) AS avail
    WHERE l.status = 'active'
      AND (
            p_query IS NULL OR
            l.title ILIKE '%' || p_query || '%' OR
            l.description ILIKE '%' || p_query || '%'
          )
      AND (p_min_price IS NULL OR l.price_per_hour >= p_min_price)
      AND (p_max_price IS NULL OR l.price_per_hour <= p_max_price)
      AND (
            p_category_ids IS NULL OR
            EXISTS (
                SELECT 1
                  FROM listing_category AS lc2
                 WHERE lc2.listing_id = l.id
                   AND lc2.category_id = ANY (p_category_ids)
            )
          )
      AND (
            p_available_from IS NULL OR p_available_to IS NULL OR
            (avail.slot_ok AND NOT avail.has_conflict)
          )
      AND (
            p_radius_km IS NULL OR geo.distance_km IS NULL OR geo.distance_km <= p_radius_km
          )
    GROUP BY l.id, l.owner_id, l.title, l.description, l.price_per_hour, l.deposit_amount,
             l.auto_confirmation, l.latitude, l.longitude, geo.distance_km,
             avail.slot_ok, avail.has_conflict
    ORDER BY
        CASE WHEN geo.distance_km IS NULL THEN 1 ELSE 0 END,
        geo.distance_km,
        l.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION fn_request_rental(
    p_listing_id uuid,
    p_lessee_id  uuid,
    p_start_at   timestamptz,
    p_end_at     timestamptz
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_listing         listing%ROWTYPE;
    v_lessee_status   text;
    v_lessor_status   text;
    v_rental_id       uuid;
    v_duration_hours  numeric;
    v_total_amount    numeric;
    v_status          text;
BEGIN
    IF p_start_at IS NULL OR p_end_at IS NULL THEN
        RAISE EXCEPTION 'Необходимо указать даты начала и окончания аренды';
    END IF;

    IF p_start_at >= p_end_at THEN
        RAISE EXCEPTION 'Дата начала аренды должна быть раньше даты окончания (получено % >= %)', p_start_at, p_end_at;
    END IF;

    SELECT * INTO v_listing
      FROM listing
     WHERE id = p_listing_id
     FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Объявление % не найдено', p_listing_id;
    END IF;

    IF v_listing.status <> 'active' THEN
        RAISE EXCEPTION 'Объявление % недоступно для аренды (статус %)', p_listing_id, v_listing.status;
    END IF;

    SELECT status INTO v_lessee_status FROM "user" WHERE id = p_lessee_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Пользователь-арендатор % не найден', p_lessee_id;
    END IF;

    IF v_lessee_status <> 'active' THEN
        RAISE EXCEPTION 'Арендатор % имеет статус %, оформление аренды запрещено', p_lessee_id, v_lessee_status;
    END IF;

    SELECT status INTO v_lessor_status FROM "user" WHERE id = v_listing.owner_id;
    IF v_lessor_status <> 'active' THEN
        RAISE EXCEPTION 'Владелец объявления имеет статус %, оформление аренды невозможно', v_lessor_status;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM blacklist
         WHERE owner_id = v_listing.owner_id
           AND blocked_user_id = p_lessee_id
    ) THEN
        RAISE EXCEPTION 'Пользователь занесён владельцем объявления в чёрный список';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM availability_slot AS s
         WHERE s.listing_id = p_listing_id
           AND s.starts_at <= p_start_at
           AND s.ends_at   >= p_end_at
    ) THEN
        RAISE EXCEPTION 'Выбранный период не входит ни в один слот доступности объявления';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM rental AS r
         WHERE r.listing_id = p_listing_id
           AND r.status IN ('pending','active')
           AND NOT (r.end_at <= p_start_at OR r.start_at >= p_end_at)
    ) THEN
        RAISE EXCEPTION 'На выбранный интервал уже существует активная или ожидающая заявка';
    END IF;

    v_duration_hours := EXTRACT(EPOCH FROM (p_end_at - p_start_at)) / 3600.0;
    v_total_amount   := ROUND(v_duration_hours * v_listing.price_per_hour, 2);
    v_status         := CASE WHEN COALESCE(v_listing.auto_confirmation, FALSE) THEN 'active' ELSE 'pending' END;

    INSERT INTO rental (listing_id, lessor_id, lessee_id, start_at, end_at, status, total_amount, deposit_amount)
    VALUES (p_listing_id, v_listing.owner_id, p_lessee_id, p_start_at, p_end_at, v_status, v_total_amount, v_listing.deposit_amount)
    RETURNING id INTO v_rental_id;

    INSERT INTO notification (user_id, type, body)
    VALUES (
        v_listing.owner_id,
        'rental_request',
        format('Новая заявка %s на объявление %s от пользователя %s', v_rental_id::text, p_listing_id::text, p_lessee_id::text)
    );

    IF v_status = 'active' THEN
        INSERT INTO notification (user_id, type, body)
        VALUES (
            p_lessee_id,
            'rental_confirmed',
            format('Заявка %s автоматически подтверждена владельцем объявления %s', v_rental_id::text, p_listing_id::text)
        );
    END IF;

    RETURN v_rental_id;
END;
$$;
```
*Комментарии к функциям*

+ Функция: *fn_register_user*

    Срабатывает при вызове во время регистрации нового пользователя.

    Она выполняет атомарную вставку в таблицу `user` с валидацией входных данных:
    - Проверяет, что `email` не пуст и уникален;
    - Проверяет формат номера телефона (10–12 цифр);
    - Если имя не указано — присваивает *«Unnamed user»*;
    - Устанавливает статус `active` по умолчанию (через дефолт поля).

    *Зачем:* гарантировать корректную регистрацию без дублирования записей и с базовой валидацией данных на уровне СУБД.
    Это предотвращает появление неконсистентных записей при параллельных регистрациях.

+ Функция: *fn_search_listings*

    Реализует бизнес-логику прецедента *«Поиск по ключевому слову»*.

    Выполняет фильтрацию и сортировку объявлений в СУБД с учётом:
    - текста запроса (`ILIKE` по `title` и `description`);
    - выбранных категорий (`category_id` в `listing_category`);
    - диапазона цен (`p_min_price`, `p_max_price`);
    - доступности по слотам (`availability_slot`) и отсутствия пересечений с активными арендами;
    - георадиуса поиска, вычисленного по координатам (формула haversine).

    Возвращает агрегированные данные по объявлениям: список категорий, расстояние до пользователя и флаг доступности.

    *Зачем:* обеспечить быстрый и гибкий поиск прямо на уровне базы, снижая нагрузку на прикладной код и улучшая производительность запросов.

+ Функция: *fn_request_rental*

    Покрывает прецедент *«Оформление заявки на аренду»*.

    Производит полную проверку и оформление аренды:
    - сверяет корректность временного интервала (`start_at < end_at`);
    - проверяет, что объявление активно, а оба пользователя существуют и имеют статус `active`;
    - учитывает чёрные списки (`blacklist`);
    - проверяет наличие подходящего слота и отсутствие пересекающихся аренд;
    - рассчитывает итоговую стоимость аренды;
    - создаёт запись в таблице `rental` и уведомления (`notification`) владельцу и арендатору.

    *Зачем:* атомарно и безопасно оформить сделку аренды, предотвращая ошибки вроде двойного бронирования или участия заблокированных пользователей.

]
