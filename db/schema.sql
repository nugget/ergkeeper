CREATE ROLE c2rkwww WITH ENCRYPTED PASSWORD 'password' LOGIN;

CREATE OR REPLACE FUNCTION onupdate_changed() RETURNS trigger AS $$
  BEGIN
    NEW.changed := (current_timestamp at time zone 'UTC');
    RETURN NEW;
  END;
$$ LANGUAGE plpgsql;

CREATE TABLE config (
	item varchar NOT NULL,
	value varchar NOT NULL,
    added timestamp(0) without time zone NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
    changed timestamp(0) without time zone NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
	comments varchar,
	PRIMARY KEY(item)
);
GRANT SELECT ON config TO c2rkwww;
CREATE TRIGGER onupdate BEFORE UPDATE ON config FOR EACH ROW EXECUTE PROCEDURE onupdate_changed();

INSERT INTO config (item,value) VALUES ('base_url','https://example.org/');
INSERT INTO config (item,value) VALUES ('rkapi_client_id','0123456789abcdef');
INSERT INTO config (item,value) VALUES ('rkapi_client_secret','0123456789abcdef');
INSERT INTO config (item,value) VALUES ('rkapi_auth_url','https://runkeeper.com/apps/authorize');
INSERT INTO config (item,value) VALUES ('rkapi_token_url','https://runkeeper.com/apps/token');
INSERT INTO config (item,value) VALUES ('allow_registration','true');

CREATE TABLE users (
	id serial NOT NULL,
    added timestamp(0) without time zone NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
    changed timestamp(0) without time zone NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
    deleted timestamp(0) without time zone,
	runkeeper_id bigint,
	runkeeper_oath_token varchar,
	facebook_id bigint,
	facebook_oath_token varchar,
	PRIMARY KEY(id)
);
GRANT ALL ON users_id_seq TO c2rkwww;
GRANT SELECT,INSERT,UPDATE ON users TO c2rkwww;
CREATE TRIGGER onupdate BEFORE UPDATE ON users FOR EACH ROW EXECUTE PROCEDURE onupdate_changed();

CREATE TABLE sessions (
	session uuid NOT NULL,
    added timestamp(0) without time zone NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
    changed timestamp(0) without time zone NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
    deleted timestamp(0) without time zone,
	user_id integer REFERENCES users(id),
	source varchar NOT NULL,
	referer varchar NOT NULL,
	ip_create inet NOT NULL,
	ip_recent inet NOT NULL,
	agent_create varchar NOT NULL,
	agent_recent varchar NOT NULL,
	PRIMARY KEY(session)
);
GRANT SELECT,INSERT,UPDATE ON sessions TO c2rkwww;
CREATE TRIGGER onupdate BEFORE UPDATE ON sessions FOR EACH ROW EXECUTE PROCEDURE onupdate_changed();
CREATE INDEX active_sessions ON sessions(session) WHERE deleted IS NULL;


