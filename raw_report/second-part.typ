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
    name         VARCHAR(100) NOT NULL,
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


]