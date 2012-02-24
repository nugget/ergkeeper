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
INSERT INTO config (item,value) VALUES ('archive_logs','false');

CREATE TABLE users (
	id bigint NOT NULL,
    added timestamp(0) without time zone NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
    changed timestamp(0) without time zone NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
    deleted timestamp(0) without time zone,
	runkeeper_oauth_token varchar,
	runkeeper_profile varchar,
	runkeeper_userinfo varchar,
	logfile_username varchar,
	post_to_facebook boolean NOT NULL DEFAULT FALSE,
	post_to_twitter boolean NOT NULL DEFAULT FALSE,
	PRIMARY KEY(id)
);
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

CREATE TABLE activities (
	id serial NOT NULL,
    added timestamp(0) without time zone NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
    changed timestamp(0) without time zone NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
    deleted timestamp(0) without time zone,
	user_id integer NOT NULL REFERENCES users(id),
    posted timestamp(0) without time zone,
	runkeeper_uri varchar,
	type varchar NOT NULL DEFAULT 'Rowing',
	start_time timestamp NOT NULL,
	total_distance bigint NOT NULL,
	duration bigint NOT NULL,
	average_heart_rate integer,
	heart_rate varchar,
	total_calories bigint,
	name varchar,
	notes varchar,
	raw varchar,
	version varchar,
	PRIMARY KEY(id)
);
GRANT ALL ON activities_id_seq TO c2rkwww;
GRANT SELECT,INSERT,UPDATE ON activities TO c2rkwww;
CREATE TRIGGER onupdate BEFORE UPDATE ON activities FOR EACH ROW EXECUTE PROCEDURE onupdate_changed();

CREATE TABLE logs (
	id serial NOT NULL,
    added timestamp(0) without time zone NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
    changed timestamp(0) without time zone NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
    deleted timestamp(0) without time zone,
	user_id integer NOT NULL REFERENCES users(id),
	csvdata text NOT NULL,
	PRIMARY KEY(id)
);
GRANT ALL ON logs_id_seq TO c2rkwww;
GRANT SELECT,INSERT ON logs TO c2rkwww;
CREATE TRIGGER logs BEFORE UPDATE ON activities FOR EACH ROW EXECUTE PROCEDURE onupdate_changed();
