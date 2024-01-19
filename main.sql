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


CREATE OR REPLACE FUNCTION assign_players_to_team() 
RETURNS VOID AS $$
DECLARE 
	player_id_to_distribute INT;
	teami INT;
	i INT;
	j INT;
	pints INT;
BEGIN
	pints := (SELECT maxPinT FROM sessions WHERE active = B'1');

    FOR i IN 1..3
    LOOP
        teami := (SELECT MIN(teamId) FROM teams WHERE active = B'1');

        FOR j in 2..pints
        LOOP
			CREATE OR REPLACE TEMPORARY VIEW playersToDistribute AS 
			SELECT playerId 
			FROM plays
			WHERE teamId IS NULL 
			ORDER BY RANDOM();
			
            SELECT playerId INTO player_id_to_distribute
            FROM playersToDistribute
            LIMIT 1;

            UPDATE plays
            SET teamId = teami
            WHERE playerId = player_id_to_distribute;
        END LOOP;

        UPDATE teams
        SET active = B'0' 
        WHERE teamId = teami;
    END LOOP;
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
	PERFORM add_people_to_team();
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
SELECT playerId 
FROM players
WHERE NOT EXISTS (
    SELECT playerId 
    FROM plays
    WHERE plays.playerId = players.playerId
);

INSERT INTO teams (teamLeaderId, teamname)
VALUES
	(1, 'Team1'),
	(2, 'Team2'),
	(3, 'Team3');