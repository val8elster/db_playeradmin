CREATE TABLE players (
    playerId SERIAL PRIMARY KEY,
    name VARCHAR(20) UNIQUE,
    points INT DEFAULT 0
);

CREATE TABLE games (
    gameId SERIAL PRIMARY KEY,
    gameLeaderId INT REFERENCES players(playerId) ON DELETE SET NULL,
    active BIT
);

CREATE TABLE teams (
    teamId SERIAL PRIMARY KEY,
    teamleaderID INT REFERENCES players(playerId) ON DELETE SET NULL,
    gameId INT REFERENCES games(gameId) ON DELETE SET NULL,
    points INT DEFAULT 0,
    teamname VARCHAR(20) UNIQUE
);

CREATE TABLE sessions (
    sessionId SERIAL PRIMARY KEY,
    maxPinT INT NOT NULL,
    active BIT
);

CREATE TABLE questions (
    questionId SERIAL PRIMARY KEY,
    answer1 VARCHAR(40) NOT NULL,
    answer2 VARCHAR(40) NOT NULL,
    answer3 VARCHAR(40) NOT NULL,
    rightAnswer VARCHAR(40) NOT NULL,
    name VARCHAR(50) NOT NULL,
    points INT NOT NULL,
    difficulty INT CHECK (difficulty IN (1,2,3,4,5))
);

CREATE TABLE answered (
    playerId INT REFERENCES players(playerId) ON DELETE SET NULL,
    questionId INT REFERENCES questions(questionId) ON DELETE SET NULL,
    isCorrect BIT,
    PRIMARY KEY(playerId, questionId)
);

CREATE TABLE plays (
    teamId INT REFERENCES teams(teamId) ON DELETE SET NULL,
    playerId INT REFERENCES players(playerId) ON DELETE SET NULL,
    gameId INT REFERENCES games(gameId) ON DELETE SET NULL,
    sessionId INT REFERENCES sessions(sessionId) ON DELETE SET NULL,
    PRIMARY KEY(playerId)
);

CREATE TABLE partOf (
    gameId INT REFERENCES games(gameId) ON DELETE SET NULL,
    sessionId INT REFERENCES sessions(sessionId) ON DELETE SET NULL,
    PRIMARY KEY(sessionId)
);

CREATE TABLE features (
    gameId INT REFERENCES games(gameId) ON DELETE SET NULL,
    questionId INT REFERENCES questions(questionId) ON DELETE SET NULL,
    PRIMARY KEY(gameId, questionId)
);

CREATE TABLE statisticsQuestions (
    questionId INT REFERENCES questions(questionId) ON DELETE SET NULL,
    rightAnswers INT DEFAULT 0,
    wrongAnswers INT DEFAULT 0
);

CREATE TABLE statisticsPlayer (
    placement INT PRIMARY KEY,
    playerId INT REFERENCES players(playerId) ON DELETE SET NULL,
    points INT DEFAULT 0,
    questionsRight INT DEFAULT 0,
    questionsWrong INT DEFAULT 0
);



CREATE OR REPLACE FUNCTION initialize()
RETURNS VOID AS $$
DECLARE
	i INT := 0;
BEGIN
	INSERT INTO sessions(maxPinT, active)
		VALUES(5, B'1');

	FOR i IN 0..2 LOOP
		INSERT INTO games(active)
			VALUES(B'1');
		INSERT INTO partOf(sessionId)
		SELECT sessionId
		FROM sessions
		WHERE active = B'1'
		AND NOT EXISTS (
			SELECT sessionId
			FROM partOf
			WHERE sessionId = sessions.sessionID
		);
	END LOOP;

	UPDATE partOf
	SET gameId = g.gameId
	FROM games g
	WHERE partOf.sessionId IN (
		SELECT s.sessionId
		FROM sessions s
		WHERE s.active = B'1'
		AND g.active = B'1'
	);
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION add_people_to_team(team_id INT, game_id INT)
RETURNS VOID AS $$
DECLARE
    	c INT := 1;
	maxPinT_value INT;
	players_needed INT;
BEGIN
    	SELECT maxPinT INTO maxPinT_value
    	FROM sessions s
	WHERE active = B'1';

    	SELECT (maxPinT_value - COUNT(*)) INTO players_needed
    	FROM plays
    	WHERE teamId = team_id AND gameId = game_id;

    	EXECUTE 'UPDATE plays
        	SET teamId = $1, gameId = $2
             	FROM (
                 	SELECT playerId, ROW_NUMBER() OVER () AS random_order
                 	FROM (
                     		SELECT playerId
                     		FROM players
                     		WHERE NOT EXISTS (
                         		SELECT teamId
                         		FROM plays
                         		WHERE plays.playerId = players.playerId
                     		)
                     		ORDER BY RANDOM()
                     		LIMIT $3
                 	) AS random_players
             	) AS selected_players
             	WHERE plays.playerId = selected_players.playerId AND plays.teamId IS NULL AND plays.gameId IS NULL'
    		USING team_id, game_id, players_needed;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION add_team_leader_to_plays()
RETURNS TRIGGER AS $$
DECLARE 
	game_session RECORD;
BEGIN
    	UPDATE plays
	SET teamId = NEW.teamId
	WHERE plays.playerId = NEW.teamLeaderId AND plays.gameId IS NULL;

	FOR game_session IN (
		SELECT gameId, sessionId
		FROM partOf
		WHERE gameId IS NOT NULL AND sessionId IS NOT NULL
 	) LOOP
		UPDATE plays
        	SET gameId = game_session.gameId
        	FROM players
        	WHERE teamId = NEW.teamId;

		UPDATE plays
        	SET sessionId = game_session.sessionId
        	WHERE teamId = NEW.teamId AND gameId = game_session.gameId;

    	END LOOP;
	RETURN NEW;
	PERFORM add_people_to_team(NEW.teamId, NEW.gameId);
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER tteamleader
AFTER INSERT ON teams
FOR EACH ROW
EXECUTE FUNCTION add_team_leader_to_plays();


INSERT INTO players (name)
VALUES
    ('Player1'),
	('Player2'),
	('Player3'),
	('Player4'),
	('Player5'),
	('Player6'),
	('Player7'),
	('Player8'),
	('Player9'),
	('Player10'),
	('Player11'),
	('Player12'),
	('Player13'),
	('Player14'),
	('Player15');

SELECT initialize();

INSERT INTO plays (playerId)
SELECT playerId FROM players;

INSERT INTO teams (teamLeaderId, teamname)
VALUES
	(1, 'Team1'),
	(2, 'Team2'),
	(3, 'Team3');