DROP DATABASE IF EXISTS CSE535Project;
CREATE DATABASE CSE535Project;
USE CSE535Project;

CREATE TABLE CUSTOMER(
	id				INT NOT NULL,
    name			VARCHAR(64) NOT NULL,
    address			VARCHAR(64) NOT NULL,
    `credit-card`	CHAR(16) NOT NULL,
    PRIMARY KEY (id)
);
CREATE TABLE STATION(
	id				INT NOT NULL,
    location		VARCHAR(64) NOT NULL,
    `num-holds`		INT NOT NULL,
    PRIMARY KEY (id)
);
CREATE TABLE AUTOPOD(
	vin			CHAR(16) NOT NULL,
    model		VARCHAR(64) NOT NULL,
    color		VARCHAR(16) NOT NULL,
    year		INT NOT NULL,
    PRIMARY KEY (vin)
);
CREATE TABLE AVAILABLE(
	vin				CHAR(16) NOT NULL,
    `station-id`	INT NOT NULL,
    FOREIGN KEY (vin) REFERENCES AUTOPOD(vin),
    FOREIGN KEY (`station-id`) REFERENCES STATION(id),
    PRIMARY KEY (vin)
);
CREATE TABLE RENTAL(
	vin			CHAR(16) NOT NULL,
    `cust-id`	INT NOT NULL,
    src			INT NOT NULL,
    date		DATE,
    time		TIME,
    FOREIGN KEY (vin) REFERENCES AUTOPOD(vin),
    FOREIGN KEY (`cust-id`) REFERENCES CUSTOMER(id),
    FOREIGN KEY (src) REFERENCES STATION(id),
    CONSTRAINT rental_pk PRIMARY KEY (vin,`cust-id`,date,time)
);
CREATE TABLE COMPLETEDTRIP(
	vin							CHAR(16) NOT NULL,
    cid							INT NOT NULL,
    `init-date`					DATE NOT NULL,
    `init-time`					TIME NOT NULL,
    `end-date`					DATE NOT NULL,
    `end-time`					TIME NOT NULL,
    `origin-station`			INT NOT NULL,
    `destination-station`		INT NOT NULL,
    cost						FLOAT NOT NULL,
    FOREIGN KEY (vin) REFERENCES AUTOPOD(vin),
    FOREIGN KEY (cid) REFERENCES CUSTOMER(id),
    CONSTRAINT origin_fk FOREIGN KEY (`origin-station`) REFERENCES STATION(id),
    CONSTRAINT destination_fk FOREIGN KEY (`destination-station`) REFERENCES STATION(id),
    CONSTRAINT ct_pk PRIMARY KEY (vin,cid,`init-date`,`init-time`)
);

/*	Add a vehicle to the system and adding it to the station with the least available spots	*/
DELIMITER //
	CREATE TRIGGER new_vehicle BEFORE INSERT ON AUTOPOD
    FOR EACH ROW
    BEGIN
		SET @places = (SELECT (STATION.`num-holds` - COUNT(AVAILABLE.`station-id`)) AS places_left
						FROM STATION LEFT JOIN AVAILABLE 
							ON STATION.id = AVAILABLE.`station-id` 
						GROUP BY STATION.location
						ORDER BY places_left DESC LIMIT 1);
		SET @station =(SELECT STATION.id AS a
					FROM STATION LEFT JOIN AVAILABLE 
						ON STATION.id = AVAILABLE.`station-id` 
					GROUP BY STATION.location
					ORDER BY (STATION.`num-holds` - COUNT(AVAILABLE.`station-id`)) DESC LIMIT 1);
		IF @places>0 THEN 
            SET FOREIGN_KEY_CHECKS=0;
            INSERT INTO AVAILABLE (vin,`station-id`)
				VALUES
                (NEW.vin,@station);
			SET FOREIGN_KEY_CHECKS=1;
		END IF;
        IF @places<=0 THEN 
			SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'You can not insert record';
		END IF;
	END//
DELIMITER ;

/*	Taking a vehicle out of order	*/
DELIMITER //
	CREATE TRIGGER delete_autopod BEFORE DELETE ON AUTOPOD
    FOR EACH ROW
    BEGIN
		SET FOREIGN_KEY_CHECKS=0;
		IF EXISTS(SELECT AVAILABLE.vin FROM AVAILABLE WHERE AVAILABLE.vin = OLD.vin) THEN
			DELETE FROM AVAILABLE WHERE AVAILABLE.vin = OLD.vin;
		ELSE SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'VEHICLE NOT AVAILABLE';
        END IF;
		SET FOREIGN_KEY_CHECKS=1;
    END//
DELIMITER ;

/*	start trip	*/
DELIMITER //
	CREATE PROCEDURE StartTrip(vin CHAR(16),cid INT)
    BEGIN
		IF (SELECT AVAILABLE.vin FROM AVAILABLE WHERE AVAILABLE.vin = vin) IS NOT NULL THEN
            IF (SELECT CUSTOMER.id FROM CUSTOMER WHERE CUSTOMER.id = cid) IS NOT NULL THEN
				SET @source = (SELECT AVAILABLE.`station-id` FROM AVAILABLE WHERE AVAILABLE.vin=vin);
                INSERT INTO RENTAL(vin,`cust-id`,src,date,time)
					VALUES
                    (vin,cid,@source,DATE(NOW()),TIME(NOW()));
				DELETE FROM AVAILABLE WHERE AVAILABLE.vin = vin;
            ELSE SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'INCORRECT DATA';
            END IF;
        ELSE SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'INCORRECT DATA';
        END IF;
    END //
DELIMITER ;

/*	end trip	*/
DELIMITER //
	CREATE PROCEDURE EndTrip(vin CHAR(16), cid INT, dest INT, cost FLOAT)
    BEGIN
    SET @dest = dest;	
    SET @places = (SELECT (STATION.`num-holds` - COUNT(AVAILABLE.`station-id`)) AS places_left
						FROM STATION LEFT JOIN AVAILABLE 
							ON STATION.id = AVAILABLE.`station-id`
						WHERE STATION.id = @dest
						GROUP BY STATION.location
						ORDER BY places_left DESC);
		IF EXISTS(SELECT RENTAL.vin, RENTAL.`cust-id` FROM RENTAL WHERE RENTAL.`cust-id` = cid AND RENTAL.vin = vin) THEN
			IF(@places)>0 THEN
				SET @`init-date` = (SELECT RENTAL.date FROM RENTAL WHERE RENTAL.vin=vin AND RENTAL.`cust-id` = cid);
				SET @`init-time` = (SELECT RENTAL.time FROM RENTAL WHERE RENTAL.vin=vin AND RENTAL.`cust-id` = cid);
				SET @source = (SELECT RENTAL.src FROM RENTAL WHERE RENTAL.vin=vin AND RENTAL.`cust-id` = cid);
				INSERT INTO COMPLETEDTRIP(vin,cid,`init-date`,`init-time`,`end-date`,`end-time`,`origin-station`,`destination-station`,cost)
					VALUES
					(vin,cid,@`init-date`,@`init-time`,DATE(NOW()),TIME(NOW()),@source,dest,cost);
				INSERT INTO AVAILABLE(vin,`station-id`)
					VALUES
					(vin,dest);
				DELETE FROM RENTAL WHERE RENTAL.vin = vin AND RENTAL.`cust-id` = cid;
			ELSE SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'STATION IS FULL';
            END IF;
		ELSE SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'INCORRECT DATA';
        END IF;
    END //
DELIMITER ;
