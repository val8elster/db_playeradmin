CREATE OR REPLACE FUNCTION change_teamname(player INT, team INT, newName VARCHAR(20))
RETURNS VOID AS $$
BEGIN 
    IF (
        (SELECT teamLeaderId 
        FROM teams
        WHERE teamId = team)
        = player
    )
    THEN
        IF NOT EXISTS (
            SELECT teamId
            FROM teams
            WHERE teamname = newName
        )
        THEN
            UPDATE teams
            SET teamname = newName
            WHERE teamId = team;
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION change_playername(player INT, newName VARCHAR(20))
RETURNS VOID AS $$
BEGIN 
    IF EXISTS (
        SELECT name 
        FROM players 
        WHERE playerId = player
    )
    THEN    
        IF NOT EXISTS (
            SELECT playerId
            FROM players
            WHERE name = newName
        )
        THEN
            UPDATE players 
            SET name = newName 
            WHERE playerId = player;
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;



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
	pl INT;
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

    FOR pl IN SELECT playerId FROM statisticsPlayer
    LOOP
        PERFORM calculate_proficiency(pl);
    END LOOP;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION calculate_proficiency(player INT)
RETURNS VOID AS $$
DECLARE
    sum INT;
BEGIN 
    sum := ((((SELECT difficulty1Answered FROM statisticsPlayer WHERE playerId = player) * 1) + 
            ((SELECT difficulty2Answered FROM statisticsPlayer WHERE playerId = player) * 4) + 
            ((SELECT difficulty3Answered FROM statisticsPlayer WHERE playerId = player) * 9) + 
            ((SELECT difficulty4Answered FROM statisticsPlayer WHERE playerId = player) * 16) + 
            ((SELECT difficulty5Answered FROM statisticsPlayer WHERE playerId = player) * 25))/10);

    UPDATE statisticsPlayer 
    SET proficiency = sum
    WHERE playerId = player;
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



-- CREATE OR REPLACE FUNCTION start_game()
-- RETURNS TRIGGER AS $$
-- DECLARE
--     game_id INT;
--     firstquestionID INT;
--     firstquestionIDname VARCHAR(50);
-- BEGIN
--     SELECT gameId INTO game_id
--     FROM games
--     WHERE active = B'1'
--     LIMIT 1;

--     INSERT INTO features(gameId,questionId, qname )
--     SELECT game_id, questionId, qname
--     FROM questions
--     WHERE questionId NOT IN (SELECT questionId FROM features WHERE gameId=game_id)
--     ORDER BY RANDOM()
--     LIMIT 1
--     RETURNING questionId, qname INTO firstquestionID, firstquestionIDname;


--     RAISE NOTICE 'Die erste Frage lautet: %', firstquestionIDname;
--     RAISE NOTICE 'Antwortmöglichkeiten:';
--     RAISE NOTICE '1. %', (SELECT answer1 FROM questions WHERE questionId = firstquestionid);
--     RAISE NOTICE '2. %', (SELECT answer2 FROM questions WHERE questionId = firstquestionid);
--     RAISE NOTICE '3. %', (SELECT answer3 FROM questions WHERE questionId = firstquestionid);
--     RAISE NOTICE '4. %', (SELECT answer4 FROM questions WHERE questionId = firstquestionid);
--     PERFORM assign_questions_batch();
-- END
-- $$ LANGUAGE plpgsql;



-- CREATE TRIGGER firstquestion
--     AFTER INSERT ON features
--     FOR EACH ROW
-- EXECUTE FUNCTION start_game();



-- CREATE OR REPLACE FUNCTION assign_next_question()
-- 	RETURNS TRIGGER AS $$
-- DECLARE
-- 	question_record RECORD;
-- BEGIN

-- 	SELECT questionId, qname
-- 	INTO question_record
-- 	FROM questions
-- 	WHERE questionId NOT IN (SELECT questionId FROM features WHERE features.gameId = NEW.gameId)
-- 	ORDER BY RANDOM()
-- 	LIMIT 1;


-- 	INSERT INTO features(gameId, questionId, qname)
-- 	VALUES (NEW.gameId, question_record.questionId, question_record.qname);

-- 	RETURN NEW;
-- END
-- $$ LANGUAGE plpgsql;



-- CREATE TRIGGER nextquestion
-- 	AFTER INSERT ON features
-- 	FOR EACH ROW
-- EXECUTE FUNCTION assign_next_question();



-- CREATE OR REPLACE FUNCTION assign_questions_batch()
--     RETURNS TRIGGER AS $$
-- DECLARE
--     question_record RECORD;
--     question_cursor CURSOR FOR
--         SELECT questionId, qname
--         FROM questions
--         WHERE questionId NOT IN (SELECT questionId FROM features WHERE NEW.gameId = features.gameId)
--         ORDER BY RANDOM()
--         LIMIT 5;
-- BEGIN
--     OPEN question_cursor;
--     FOR question_record IN question_cursor
--         LOOP
--             INSERT INTO features(gameId, questionId, qname)
--             VALUES (NEW.gameId, question_record.questionId, question_record.qname);
--         END LOOP;
--     CLOSE question_cursor;
--     RETURN NEW;
-- END
-- $$ LANGUAGE plpgsql;


-- CREATE TRIGGER assignquestion
--     AFTER INSERT ON features
--     FOR EACH ROW
-- EXECUTE PROCEDURE assign_questions_batch();



CREATE OR REPLACE FUNCTION add_questions_to_session(quest1 INT, quest2 INT, quest3 INT, quest4 INT, quest5 INT)
RETURNS VOID AS $$
DECLARE
    game INT;
	i INT;
BEGIN
    game := (SELECT MIN(gameId) FROM games WHERE active = B'1');

    IF (quest1 <> quest2 AND quest1 <> quest3 AND quest1 <> quest4 AND quest1 <> quest5
	   AND quest2 <> quest3 AND quest2 <> quest4 AND quest2 <> quest5
	   AND quest3 <> quest4 AND quest3 <> quest5
	   AND quest4 <> quest5)
    THEN
        IF ((SELECT MAX(questionId) FROM questions) >= GREATEST(quest1, quest2, quest3, quest4, quest5))
        THEN
            FOR i in 0..2
            LOOP
                IF((SELECT COUNT(questionId) FROM features WHERE gameId = game) = 0)
                THEN
                    INSERT INTO features (questionId, gameId)
                    VALUES
                        (quest1, game),
                        (quest2, game),
                        (quest3, game),
                        (quest4, game),
                        (quest5, game);
                END IF;
                game := game + 1;
            END LOOP;
        END IF;
    END IF;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION first_question()
RETURNS VOID AS $$
DECLARE 
    game INT;
    firstQuestion INT;
BEGIN 
    game := (SELECT MIN(gameId) FROM games WHERE active = B'1');

    firstQuestion := (SELECT MIN(questionId) FROM features WHERE gameId = game AND called = B'0');

    UPDATE features
    SET called = B'1'
    WHERE questionId = firstQuestion;

    RAISE NOTICE 'First Question: %', (SELECT qname FROM questions WHERE questionId = firstQuestion);
    RAISE NOTICE 'Answers: %', firstQuestion;
    RAISE NOTICE 'A: %', (SELECT answer1 FROM questions WHERE questionId = firstQuestion);
    RAISE NOTICE 'B: %', (SELECT answer2 FROM questions WHERE questionId = firstQuestion);
    RAISE NOTICE 'C: %', (SELECT answer3 FROM questions WHERE questionId = firstQuestion);
    RAISE NOTICE 'D: %', (SELECT answer1 FROM questions WHERE questionId = firstQuestion);
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION followUp()
RETURNS VOID AS $$
DECLARE
    game INT;
    question INT;
BEGIN
    SELECT MIN(gameId) INTO game FROM features WHERE called = B'0';
    SELECT MIN(questionId) INTO question FROM features WHERE gameId = game AND called = B'0';

    IF question IS NOT NULL THEN
        UPDATE features
        SET called = B'1'
        WHERE questionId = question;

        RAISE NOTICE 'Question: %', (SELECT qname FROM questions WHERE questionId = question);
        RAISE NOTICE 'Answers: %', question;
        RAISE NOTICE 'A: %', (SELECT answer1 FROM questions WHERE questionId = question);
        RAISE NOTICE 'B: %', (SELECT answer2 FROM questions WHERE questionId = question);
        RAISE NOTICE 'C: %', (SELECT answer3 FROM questions WHERE questionId = question);
        RAISE NOTICE 'D: %', (SELECT answer4 FROM questions WHERE questionId = question);
    ELSE
        RAISE NOTICE 'No unanswered questions found for the current game.';
    END IF;
END;
$$ LANGUAGE plpgsql;




CREATE OR REPLACE FUNCTION check_correct()
RETURNS TRIGGER AS $$
BEGIN 
    IF(NEW.isCorrect = B'0')
    THEN
        PERFORM followUp();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE TRIGGER tnextquestion
    BEFORE INSERT ON answered
    FOR EACH STATEMENT
    EXECUTE FUNCTION check_correct();



CREATE OR REPLACE FUNCTION add_difficulty_answer(question INT, player INT)
RETURNS VOID AS $$
DECLARE 
    diff INT;
BEGIN 
    diff := (SELECT difficulty 
            FROM statisticsQuestions
            WHERE questionID = question);
			
    UPDATE statisticsPlayer
    SET 
        difficulty1Answered = difficulty1Answered + CASE WHEN diff = 1 THEN 1 ELSE 0 END,
        difficulty2Answered = difficulty2Answered + CASE WHEN diff = 2 THEN 1 ELSE 0 END,
        difficulty3Answered = difficulty3Answered + CASE WHEN diff = 3 THEN 1 ELSE 0 END,
        difficulty4Answered = difficulty4Answered + CASE WHEN diff = 4 THEN 1 ELSE 0 END,
        difficulty5Answered = difficulty5Answered + CASE WHEN diff = 5 THEN 1 ELSE 0 END
    WHERE playerId = player;
END;
$$ LANGUAGE plpgsql;



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
		
		PERFORM add_difficulty_answer(question, player);
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
		dif := 1;
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