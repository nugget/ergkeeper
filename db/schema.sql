CREATE ROLE c2rkwww WITH ENCRYPTED PASSWORD 'password' LOGIN;

CREATE TABLE config (
	item varchar NOT NULL,
	value varchar NOT NULL,
    added timestamp(0) without time zone NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
    changed timestamp(0) without time zone NOT NULL DEFAULT (current_timestamp at time zone 'utc'),
	comments varchar,
	PRIMARY KEY(item)
);
GRANT SELECT ON config TO c2rkwww;

INSERT INTO config (item,value) VALUES ('base_url','https://example.org/');
INSERT INTO config (item,value) VALUES ('rkapi_client_id','0123456789abcdef');
INSERT INTO config (item,value) VALUES ('rkapi_client_secret','0123456789abcdef');
INSERT INTO config (item,value) VALUES ('rkapi_auth_url','https://runkeeper.com/apps/authorize');
INSERT INTO config (item,value) VALUES ('rkapi_token_url','https://runkeeper.com/apps/token');

