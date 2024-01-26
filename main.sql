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
    teamname VARCHAR(20) UNIQUE,
	active BIT
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
    answer4 VARCHAR(40) NOT NULL,
    rightAnswer INT CHECK (rightAnswer IN (1,2,3,4)),
    qname VARCHAR(50) NOT NULL,
    points INT NOT NULL,
    UNIQUE(qname, questionId)
);



CREATE TABLE answered (
	nom SERIAL PRIMARY KEY,
    playerId INT REFERENCES players(playerId) ON DELETE SET NULL,
    questionId INT REFERENCES questions(questionId) ON DELETE SET NULL,
    isCorrect BIT,
	added BIT
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
    qname VARCHAR(50),
    PRIMARY KEY(gameId, questionId),
    FOREIGN KEY(questionId, qname) REFERENCES questions(questionId, qname)
);



CREATE TABLE statisticsQuestions (
    questionId INT REFERENCES questions(questionId) ON DELETE CASCADE,
    rightAnswers INT DEFAULT 0,
    wrongAnswers INT DEFAULT 0,
	difficulty INT CHECK (difficulty IN (0,1,2,3,4,5))
);



CREATE TABLE statisticsPlayer (
    placement INT UNIQUE,    
	playerId INT REFERENCES players(playerId) ON DELETE SET NULL,
    points INT DEFAULT 0,
    questionRatio INT DEFAULT 0,
	PRIMARY KEY(playerId)
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



CREATE OR REPLACE FUNCTION decomp()
RETURNS VOID AS $$
BEGIN
    UPDATE sessions
    SET active = B'0'
    WHERE active = B'1';

    UPDATE games
    SET active = B'0'
    WHERE active = B'1';

    UPDATE teams
    SET active = B'0'
    WHERE active = B'1';

    UPDATE plays
    SET teamId = NULL, gameId = NULL
    WHERE teamId IS NOT NULL;

	PERFORM update_stats();
	PERFORM calculate_points();
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION update_stats()
RETURNS VOID AS $$
DECLARE 
BEGIN 
	WITH RankedPlayers AS (
		SELECT
			sp.playerId,
			p.points,
			sp.questionRatio,
			ROW_NUMBER() OVER (ORDER BY p.points DESC, sp.questionRatio DESC, sp.playerId) AS placement
		FROM
			statisticsPlayer sp
		JOIN players p ON sp.playerId = p.playerId
	)
	
	UPDATE statisticsPlayer sp
	SET 
		points = rp.points,
		questionRatio = rp.questionRatio,
		placement = rp.placement
	FROM RankedPlayers rp
	WHERE sp.playerId = rp.playerId;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION calculate_points()
RETURNS VOID AS $$
BEGIN 
	UPDATE questions q
	SET points = sq.difficulty * 10
	FROM statisticsQuestions sq
	WHERE q.questionId = sq.questionId;
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

        END LOOP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;



CREATE TRIGGER tteamleader
    AFTER INSERT ON teams
    FOR EACH ROW
EXECUTE FUNCTION add_team_leader_to_plays();



CREATE OR REPLACE FUNCTION start_game()
RETURNS TRIGGER AS $$
DECLARE
    game_id INT;
    firstquestionID INT;
    firstquestionIDname VARCHAR(50);
BEGIN
    SELECT gameId INTO game_id
    FROM games
    WHERE active = B'1'
    LIMIT 1;

    INSERT INTO features(gameId,questionId, qname )
    SELECT game_id, questionId, qname
    FROM questions
    WHERE questionId NOT IN (SELECT questionId FROM features WHERE gameId=game_id)
    ORDER BY RANDOM()
    LIMIT 1
    RETURNING questionId, qname INTO firstquestionID, firstquestionIDname;


    RAISE NOTICE 'Die erste Frage lautet: %', firstquestionIDname;
    RAISE NOTICE 'Antwortmöglichkeiten:';
    RAISE NOTICE '1. %', (SELECT answer1 FROM questions WHERE questionId = firstquestionid);
    RAISE NOTICE '2. %', (SELECT answer2 FROM questions WHERE questionId = firstquestionid);
    RAISE NOTICE '3. %', (SELECT answer3 FROM questions WHERE questionId = firstquestionid);
    RAISE NOTICE '4. %', (SELECT answer4 FROM questions WHERE questionId = firstquestionid);
    PERFORM assign_questions_batch();
END
$$ LANGUAGE plpgsql;



CREATE TRIGGER firstquestion
    AFTER INSERT ON features
    FOR EACH ROW
EXECUTE FUNCTION start_game();



CREATE OR REPLACE FUNCTION assign_next_question()
	RETURNS TRIGGER AS $$
DECLARE
	question_record RECORD;
BEGIN

	SELECT questionId, qname
	INTO question_record
	FROM questions
	WHERE questionId NOT IN (SELECT questionId FROM features WHERE features.gameId = NEW.gameId)
	ORDER BY RANDOM()
	LIMIT 1;


	INSERT INTO features(gameId, questionId, qname)
	VALUES (NEW.gameId, question_record.questionId, question_record.qname);

	RETURN NEW;
END
$$ LANGUAGE plpgsql;



CREATE TRIGGER nextquestion
	AFTER INSERT ON features
	FOR EACH ROW
EXECUTE FUNCTION assign_next_question();



CREATE OR REPLACE FUNCTION assign_questions_batch()
    RETURNS TRIGGER AS $$
DECLARE
    question_record RECORD;
    question_cursor CURSOR FOR
        SELECT questionId, qname
        FROM questions
        WHERE questionId NOT IN (SELECT questionId FROM features WHERE NEW.gameId = features.gameId)
        ORDER BY RANDOM()
        LIMIT 5;
BEGIN
    OPEN question_cursor;
    FOR question_record IN question_cursor
        LOOP
            INSERT INTO features(gameId, questionId, qname)
            VALUES (NEW.gameId, question_record.questionId, question_record.qname);
        END LOOP;
    CLOSE question_cursor;
    RETURN NEW;
END
$$ LANGUAGE plpgsql;


CREATE TRIGGER assignquestion
    AFTER INSERT ON features
    FOR EACH ROW
EXECUTE PROCEDURE assign_questions_batch();



CREATE OR REPLACE FUNCTION answer_question(question INT, answer INT, player INT)
RETURNS VOID AS $$
DECLARE
	correct BIT;
	team INT;
	prevPPoints INT;
	prevTpoints INT;
	qPoints INT;
BEGIN
	IF(
		(SELECT rightAnswer
		FROM questions
		WHERE (questionId = question))
		= answer
	)
	THEN
		correct := B'0';
		-- true

		team := (SELECT teamId FROM plays WHERE playerId = player);

		prevPPoints := (SELECT points FROM players WHERE playerId = player);
		prevTPoints := (SELECT points FROM teams WHERE teamId = team);
		qPoints := (SELECT points FROM questions WHERE questionId = question);

		UPDATE players SET points = (prevPPoints + qPoints) WHERE playerId = player;
		UPDATE teams SET points = (prevTPoints + qPoints) WHERE teamId = team;

		UPDATE statisticsPlayer SET questionRatio = (questionRatio + 1) WHERE playerId = player;
	ELSE
		correct := B'1';
		-- false

		UPDATE statisticsPlayer SET questionRatio = (questionRatio - 1) WHERE playerId = player;
	END IF;

	INSERT INTO answered (playerId, questionId, isCorrect, added)
	VALUES (player, question, correct, B'1');
END;
$$ LANGUAGE plpgsql;


-- falsch: 0-20%: 1, 30-40%: 2, 50-60%: 3, 70-80%: 4, 90-100%: 5
CREATE OR REPLACE FUNCTION check_difficulty(question_row INT)
RETURNS VOID AS $$
DECLARE
	dif INT;
	righta INT;
	wronga INT;
	question_id INT;
BEGIN
	SELECT questionId INTO question_id
	FROM answered
	WHERE nom = question_row;

	SELECT rightAnswers, wrongAnswers INTO righta, wronga
    FROM statisticsQuestions
    WHERE questionId = question_id;

	IF (righta + wronga != 0)
	THEN
		dif := ((10 - (righta * 10) / (righta + wronga)) / 2);
		IF(dif = 0)
		THEN
			dif := 1;
		END IF;
	ELSE
		dif := 0;
	END IF;


	UPDATE statisticsQuestions
	SET difficulty = dif
	WHERE questionId = question_id;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION create_statistic_for_question()
RETURNS TRIGGER AS $$
DECLARE
    question_id INT;
	col INT;
BEGIN
    SELECT questionId INTO question_id
    FROM answered
	ORDER BY nom DESC
    LIMIT 1;

	SELECT nom into col
	FROM answered
	ORDER BY nom DESC
	LIMIT 1;

    IF (SELECT isCorrect FROM answered WHERE nom = col) = B'0'
	THEN
        UPDATE statisticsQuestions
        SET rightAnswers = rightAnswers + 1
        WHERE questionId = question_id;
    ELSE
        UPDATE statisticsQuestions
        SET wrongAnswers = wrongAnswers + 1
        WHERE questionId = question_id;
    END IF;

	UPDATE answered
	SET added = B'0'
	WHERE added = B'1';

	PERFORM check_difficulty(col);

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tqueststat
AFTER INSERT ON answered
FOR EACH STATEMENT
EXECUTE FUNCTION create_statistic_for_question();





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
	


INSERT INTO statisticsPlayer (playerId)
VALUES
	(1),
	(2),
	(3),
	(4),
	(5),
	(6),
	(7),
	(8),
	(9),
	(10),
	(11),
	(12),
	(13), 
	(14), 
	(15);



SELECT initialize();



INSERT INTO plays (playerId)
VALUES 
	(1), 
	(2), 
	(3);



INSERT INTO teams (teamname, teamLeaderId, active)
VALUES
	('Team1', 1, B'1'),
	('Team2', 2, B'1'),
	('Team3', 3, B'1');



INSERT INTO plays (playerId, teamId, gameId)
SELECT playerId, 1, 1
FROM players
WHERE NOT EXISTS (
    SELECT playerId 
    FROM plays
    WHERE plays.playerId = players.playerId
)
LIMIT 4;



INSERT INTO plays (playerId, teamId, gameId)
SELECT playerId, 2, 1
FROM players
WHERE NOT EXISTS (
    SELECT playerId 
    FROM plays
    WHERE plays.playerId = players.playerId
)
LIMIT 4;



INSERT INTO plays (playerId, teamId, gameId)
SELECT playerId, 3, 1
FROM players
WHERE NOT EXISTS (
    SELECT playerId
    FROM plays
    WHERE plays.playerId = players.playerId
)
LIMIT 4;



INSERT INTO questions(questionId, qname, answer1, answer2, answer3, answer4, rightanswer, points)
VALUES
    (1, 'welche farbe hat der Himmel?', 'blau', 'gelb', 'pink', 'grün',1, 30),
    (2, 'was ist Schnee','wasser','blut','Himbeersaft','Cola',1, 20),
    (3, 'welche farbe hat die Milch?', 'blau', 'gelb', 'pink', 'weiß', 4, 50),
    (4, 'was ist ein Baum ', 'wasser', 'Pflanze', 'Himbeersaft', 'Cola', 2, 10),
    (5, 'welche farbe hat der Mars?', 'schwarz', 'Schokolade', 'orange', 'grün', 3, 10),
    (6, 'was ist eis','wasser', 'lecker', 'Himbeersaft', 'Cola', 2, 10),
    (7, 'welche farbe hat das wasser?', 'blau', 'kalt', 'Loch Ness', 'grün', 3, 10),
    (8, 'was ist eine Katze', 'wasser', 'Tier', 'Himbeersaft', 'Süß', 4, 10),
	(9, 'ist der himmel blau?' , 'blubb', 'A', 'miau', 'ich bin farbenblind', 4, 1);



INSERT INTO statisticsQuestions(questionId, difficulty)
VALUES
	(1, 1),
	(2, 1),
	(3, 1),
	(4, 1),
	(5, 1),
	(6, 1),
	(7, 1),
	(8, 1),
	(9, 1);



-- question, answer, player
SELECT answer_question(1, 1, 1);
SELECT answer_question(1, 1, 1);
SELECT answer_question(1, 1, 1);
SELECT answer_question(1, 1, 1);
SELECT answer_question(1, 1, 1);
SELECT answer_question(1, 1, 1);
SELECT answer_question(1, 1, 1);
SELECT answer_question(1, 3, 1);
SELECT answer_question(1, 2, 1);
SELECT answer_question(1, 3, 1);

SELECT answer_question(3, 4, 2);

SELECT answer_question(7, 2, 5);

SELECT decomp();